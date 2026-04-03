import { NextRequest } from 'next/server';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';

const REGION = process.env.AWS_REGION || 'ap-northeast-2';
const ATHENA_LAMBDA = process.env.ATHENA_LAMBDA || 'rum-pipeline-athena-query';
const BEDROCK_MODEL = process.env.BEDROCK_MODEL || 'anthropic.claude-sonnet-4-20250514-v1:0';

const lambda = new LambdaClient({ region: REGION });

const SYSTEM_PROMPT = `당신은 RUM (Real User Monitoring) 데이터 분석 전문가입니다.
관리자의 자연어 질문을 분석하여 Athena SQL을 생성하고, 결과를 해석하여 한국어로 답변합니다.

## RUM 스키마
DB: rum_pipeline_db, 테이블: rum_events
컬럼: session_id, user_id, device_id, timestamp(bigint ms), app_version, event_type, event_name, payload(JSON), context(JSON)
파티션: platform('web'|'ios'|'android'), year, month, day, hour (모두 string)
payload 접근: json_extract_scalar(payload, '$.value')
context 접근: json_extract_scalar(context, '$.device.browser')
항상 year/month/day 파티션 필터 포함. 오늘: year='2026', month='04', day='03'`;

async function queryAthena(sql: string): Promise<string> {
  const resp = await lambda.send(new InvokeCommand({
    FunctionName: ATHENA_LAMBDA,
    Payload: Buffer.from(JSON.stringify({ input: { sql } })),
  }));
  return new TextDecoder().decode(resp.Payload);
}

async function callBedrock(messages: Array<{role: string; content: string}>): Promise<ReadableStream> {
  // Use Bedrock Converse API via fetch (streaming)
  const { SignatureV4 } = await import('@smithy/signature-v4');
  const { Sha256 } = await import('@aws-crypto/sha256-js');
  const { defaultProvider } = await import('@aws-sdk/credential-provider-node');

  const credentials = await defaultProvider()();
  const signer = new SignatureV4({
    service: 'bedrock',
    region: REGION,
    credentials,
    sha256: Sha256,
  });

  const body = JSON.stringify({
    anthropic_version: 'bedrock-2023-05-31',
    max_tokens: 4096,
    system: SYSTEM_PROMPT,
    messages: messages.map(m => ({ role: m.role, content: m.content })),
    stream: true,
  });

  const url = `https://bedrock-runtime.${REGION}.amazonaws.com/model/${BEDROCK_MODEL}/invoke-with-response-stream`;

  const request = await signer.sign({
    method: 'POST',
    protocol: 'https:',
    hostname: `bedrock-runtime.${REGION}.amazonaws.com`,
    path: `/model/${BEDROCK_MODEL}/invoke-with-response-stream`,
    headers: {
      'content-type': 'application/json',
      host: `bedrock-runtime.${REGION}.amazonaws.com`,
    },
    body,
  });

  const resp = await fetch(url, {
    method: 'POST',
    headers: request.headers as Record<string, string>,
    body,
  });

  if (!resp.ok) {
    throw new Error(`Bedrock error: ${resp.status} ${await resp.text()}`);
  }

  return resp.body!;
}

export async function POST(request: NextRequest) {
  const { prompt, sessionId } = await request.json();

  if (!prompt) {
    return new Response(JSON.stringify({ error: 'prompt is required' }), { status: 400 });
  }

  const encoder = new TextEncoder();

  // Simple approach: call Athena first to get context, then stream Bedrock response
  const stream = new ReadableStream({
    async start(controller) {
      try {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'start' })}\n\n`));

        // Step 1: Get RUM summary data for context
        const summaryResult = await queryAthena(
          "SELECT event_type, COUNT(*) as cnt FROM rum_pipeline_db.rum_events WHERE year='2026' AND month='04' GROUP BY 1 ORDER BY 2 DESC"
        );

        // Step 2: Call Bedrock with user prompt + data context
        const messages = [{
          role: 'user',
          content: `${prompt}\n\n[참고 데이터]\n현재 RUM 데이터 요약:\n${summaryResult}\n\n필요하면 추가 SQL을 제안해주세요. Athena SQL은 코드블록으로 감싸주세요.`,
        }];

        // For now, use non-streaming Bedrock invoke
        const { BedrockRuntimeClient, InvokeModelCommand } = await import('@aws-sdk/client-bedrock-runtime');
        const bedrock = new BedrockRuntimeClient({ region: REGION });

        const bedrockResp = await bedrock.send(new InvokeModelCommand({
          modelId: BEDROCK_MODEL,
          contentType: 'application/json',
          accept: 'application/json',
          body: JSON.stringify({
            anthropic_version: 'bedrock-2023-05-31',
            max_tokens: 4096,
            system: SYSTEM_PROMPT,
            messages: [{ role: 'user', content: messages[0].content }],
          }),
        }));

        const result = JSON.parse(new TextDecoder().decode(bedrockResp.body));
        const responseText = result.content?.[0]?.text || '응답을 생성할 수 없습니다.';

        // Stream response in chunks (SSE)
        const chunkSize = 30;
        for (let i = 0; i < responseText.length; i += chunkSize) {
          const chunk = responseText.slice(i, i + chunkSize);
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'chunk', content: chunk })}\n\n`));
          await new Promise((r) => setTimeout(r, 5));
        }

        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'done' })}\n\n`));
      } catch (error: unknown) {
        const message = error instanceof Error ? error.message : 'Unknown error';
        console.error('Chat error:', message);
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'error', content: message })}\n\n`));
      } finally {
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    },
  });
}
