import { NextRequest } from 'next/server';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';

const REGION = process.env.AWS_REGION || 'ap-northeast-2';
const ATHENA_LAMBDA = process.env.ATHENA_LAMBDA || 'rum-pipeline-athena-query';
const BEDROCK_MODEL = process.env.BEDROCK_MODEL || 'global.anthropic.claude-sonnet-4-6';

const lambda = new LambdaClient({ region: REGION });

const SYSTEM_PROMPT = `당신은 RUM (Real User Monitoring) 데이터 분석 전문가입니다.

## 핵심 동작 방식
1. 사용자 질문을 받으면, 먼저 Athena SQL을 생성하여 <SQL> 태그로 감싸세요
2. 시스템이 SQL을 자동 실행하고 결과를 돌려줍니다
3. 결과를 받으면 한국어로 분석하고 인사이트를 제공하세요
4. 추가 분석이 필요하면 <SQL> 태그로 추가 쿼리를 요청할 수 있습니다

## SQL 작성 시 반드시 지켜야 할 규칙
- 테이블: rum_pipeline_db.rum_events
- 파티션 필터 필수: year, month, day (모두 string)
- 오늘 날짜: year='2026', month='04', day='03'
- 어제: day='02'
- JSON 접근: json_extract_scalar(payload, '$.value'), json_extract_scalar(context, '$.device.browser')
- event_name은 소문자: 'lcp', 'cls', 'inp' (대문자 아님!)
- page URL: json_extract_scalar(context, '$.url')
- screen: json_extract_scalar(context, '$.screen_name')
- LIMIT 사용 권장

## 스키마
- session_id, user_id, device_id, timestamp(bigint ms), app_version
- event_type: 'performance'|'action'|'error'|'navigation'|'resource'
- event_name: lcp, cls, inp, page_view, screen_view, click, tap, js_error, crash, fetch, xhr 등
- payload(JSON): $.value, $.rating, $.message, $.stack, $.filename, $.url, $.duration, $.transferSize
- context(JSON): $.url, $.screen_name, $.device.os, $.device.browser, $.device.model, $.connection.type
- 파티션: platform('web'|'ios'|'android'), year, month, day, hour

## SQL 태그 형식
<SQL>SELECT ... FROM rum_pipeline_db.rum_events WHERE ...</SQL>

## 응답 형식
- 결과를 마크다운 표로 정리
- 핵심 인사이트 요약
- 개선 제안 (있으면)
- 항상 한국어`;

async function queryAthena(sql: string): Promise<string> {
  try {
    const command = new InvokeCommand({
      FunctionName: ATHENA_LAMBDA,
      Payload: Buffer.from(JSON.stringify({ input: { sql } })),
    });
    const resp = await lambda.send(command);
    const payload = new TextDecoder().decode(resp.Payload);
    return payload;
  } catch (e) {
    return JSON.stringify({ error: `Athena 쿼리 실패: ${e}` });
  }
}

function extractSQL(text: string): string[] {
  const matches = text.match(/<SQL>([\s\S]*?)<\/SQL>/gi);
  if (!matches) return [];
  return matches.map(m => m.replace(/<\/?SQL>/gi, '').trim());
}

async function callBedrock(messages: Array<{role: string; content: string}>): Promise<string> {
  const { BedrockRuntimeClient, InvokeModelCommand } = await import('@aws-sdk/client-bedrock-runtime');
  const bedrock = new BedrockRuntimeClient({ region: REGION });

  const resp = await bedrock.send(new InvokeModelCommand({
    modelId: BEDROCK_MODEL,
    contentType: 'application/json',
    accept: 'application/json',
    body: JSON.stringify({
      anthropic_version: 'bedrock-2023-05-31',
      max_tokens: 4096,
      system: SYSTEM_PROMPT,
      messages: messages.map(m => ({ role: m.role, content: m.content })),
    }),
  }));

  const result = JSON.parse(new TextDecoder().decode(resp.body));
  return result.content?.[0]?.text || '';
}

export async function POST(request: NextRequest) {
  const { prompt } = await request.json();
  if (!prompt) {
    return new Response(JSON.stringify({ error: 'prompt is required' }), { status: 400 });
  }

  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      const send = (data: object) => {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify(data)}\n\n`));
      };

      try {
        send({ type: 'start' });
        send({ type: 'chunk', content: '🔍 질문을 분석하고 있습니다...\n\n' });

        const messages: Array<{role: string; content: string}> = [
          { role: 'user', content: prompt }
        ];

        // Round 1: Bedrock generates SQL
        const response1 = await callBedrock(messages);
        const sqls = extractSQL(response1);

        if (sqls.length === 0) {
          // No SQL needed - just return the response
          const chunks = response1.match(/[\s\S]{1,30}/g) || [response1];
          for (const chunk of chunks) {
            send({ type: 'chunk', content: chunk });
            await new Promise(r => setTimeout(r, 5));
          }
          send({ type: 'done' });
          controller.close();
          return;
        }

        // Execute SQL queries
        send({ type: 'chunk', content: '📊 데이터를 조회하고 있습니다...\n\n' });

        let queryResults = '';
        for (const sql of sqls) {
          send({ type: 'chunk', content: `\`\`\`sql\n${sql}\n\`\`\`\n\n` });
          const result = await queryAthena(sql);

          try {
            const parsed = JSON.parse(result);
            if (parsed.error) {
              queryResults += `쿼리 실패: ${parsed.error}\n`;
              send({ type: 'chunk', content: `⚠️ 쿼리 오류: ${parsed.error}\n\n` });
            } else {
              queryResults += `쿼리 결과 (${parsed.rowCount}행):\n${JSON.stringify(parsed.data, null, 2)}\n\n`;
              send({ type: 'chunk', content: `✅ ${parsed.rowCount}개 결과 조회 완료\n\n` });
            }
          } catch {
            queryResults += `결과: ${result}\n`;
          }
        }

        // Multi-round loop: Bedrock analyzes, may request more SQL
        messages.push({ role: 'assistant', content: response1 });
        messages.push({
          role: 'user',
          content: `위 SQL 쿼리의 실행 결과입니다. 이 데이터를 바탕으로 분석해주세요. 추가 데이터가 필요하면 <SQL> 태그로 요청하세요.\n\n${queryResults}`
        });

        const MAX_ROUNDS = 3;
        for (let round = 2; round <= MAX_ROUNDS + 1; round++) {
          send({ type: 'chunk', content: '🤖 결과를 분석하고 있습니다...\n\n---\n\n' });

          const roundResponse = await callBedrock(messages);
          const moreSqls = extractSQL(roundResponse);

          if (moreSqls.length === 0 || round > MAX_ROUNDS) {
            // No more SQL - stream final analysis
            const cleanResponse = roundResponse.replace(/<SQL>[\s\S]*?<\/SQL>/gi, '').trim();
            const chunks = cleanResponse.match(/[\s\S]{1,30}/g) || [cleanResponse];
            for (const chunk of chunks) {
              send({ type: 'chunk', content: chunk });
              await new Promise(r => setTimeout(r, 5));
            }
            break;
          }

          // Execute additional SQL queries
          send({ type: 'chunk', content: '📊 추가 데이터를 조회하고 있습니다...\n\n' });
          let moreResults = '';
          for (const sql of moreSqls) {
            send({ type: 'chunk', content: `\`\`\`sql\n${sql}\n\`\`\`\n\n` });
            const result = await queryAthena(sql);
            try {
              const parsed = JSON.parse(result);
              if (parsed.error) {
                moreResults += `쿼리 실패: ${parsed.error}\n`;
                send({ type: 'chunk', content: `⚠️ ${parsed.error}\n\n` });
              } else {
                moreResults += `쿼리 결과 (${parsed.rowCount}행):\n${JSON.stringify(parsed.data, null, 2)}\n\n`;
                send({ type: 'chunk', content: `✅ ${parsed.rowCount}개 결과 조회 완료\n\n` });
              }
            } catch {
              moreResults += `결과: ${result}\n`;
            }
          }

          messages.push({ role: 'assistant', content: roundResponse });
          messages.push({
            role: 'user',
            content: `추가 쿼리 결과입니다. 모든 데이터를 종합하여 최종 분석을 마크다운으로 작성하세요. 더 이상 <SQL> 태그를 사용하지 마세요.\n\n${moreResults}`
          });
        }

        send({ type: 'done' });
      } catch (error: unknown) {
        const message = error instanceof Error ? error.message : 'Unknown error';
        console.error('Chat error:', message);
        send({ type: 'error', content: message });
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
