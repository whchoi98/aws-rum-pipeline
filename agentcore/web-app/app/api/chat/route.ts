import { NextRequest } from 'next/server';
import { LambdaClient, InvokeCommand } from '@aws-sdk/client-lambda';
import { CloudWatchLogsClient, FilterLogEventsCommand } from '@aws-sdk/client-cloudwatch-logs';
import { CloudWatchClient, GetMetricStatisticsCommand, DescribeAlarmsCommand } from '@aws-sdk/client-cloudwatch';
import { GlueClient, GetTableCommand } from '@aws-sdk/client-glue';
import { SNSClient, PublishCommand } from '@aws-sdk/client-sns';

const REGION = process.env.AWS_REGION || 'ap-northeast-2';
const ATHENA_LAMBDA = process.env.ATHENA_LAMBDA || 'rum-pipeline-athena-query';
const BEDROCK_MODEL = process.env.BEDROCK_MODEL || 'global.anthropic.claude-sonnet-4-6';
const SNS_TOPIC_ARN = process.env.SNS_TOPIC_ARN || '';
const GRAFANA_URL = process.env.GRAFANA_URL || '';
const GRAFANA_API_KEY = process.env.GRAFANA_API_KEY || '';
const PROJECT_NAME = process.env.PROJECT_NAME || 'rum-pipeline';

const lambdaClient = new LambdaClient({ region: REGION });
const cwLogs = new CloudWatchLogsClient({ region: REGION });
const cw = new CloudWatchClient({ region: REGION });
const glue = new GlueClient({ region: REGION });
const sns = new SNSClient({ region: REGION });

const SYSTEM_PROMPT = `당신은 RUM (Real User Monitoring) 데이터 분석 전문가입니다.

## 핵심 동작 방식
1. 사용자 질문을 받으면 적절한 도구 태그를 생성하세요
2. 시스템이 태그를 자동 실행하고 결과를 돌려줍니다
3. 결과를 받으면 한국어로 분석하고 인사이트를 제공하세요

## 사용 가능한 도구 태그

### Athena SQL 쿼리 (기본)
<SQL>SELECT ... FROM rum_pipeline_db.rum_events WHERE ...</SQL>

### CloudWatch 로그 검색
<CWLOGS>{"logGroup":"/aws/lambda/${PROJECT_NAME}-ingest","pattern":"ERROR","minutes":30}</CWLOGS>

### CloudWatch 메트릭 조회
<METRICS>{"namespace":"AWS/Lambda","metricName":"Errors","dimensions":"FunctionName=${PROJECT_NAME}-ingest","minutes":60,"stat":"Sum"}</METRICS>

### CloudWatch 알람 상태
<ALARM>{"stateFilter":"ALARM","prefix":"${PROJECT_NAME}"}</ALARM>

### Glue 테이블 스키마
<GLUE>{"table":"rum_events","database":"rum_pipeline_db"}</GLUE>

### Grafana 어노테이션
<GRAFANA>{"text":"에러율 급증 감지","tags":"agent,alert"}</GRAFANA>

### SNS 알림 발송
<SNS>{"subject":"RUM 분석 리포트","message":"에러율이 10%를 초과했습니다"}</SNS>

## SQL 규칙
- 테이블: rum_pipeline_db.rum_events
- 파티션 필터 필수: year, month, day (string)
- 오늘: year='2026', month='04', day='07'
- JSON: json_extract_scalar(payload, '$.value')
- event_name 소문자: 'lcp', 'cls', 'inp'

## 스키마
- session_id, user_id, device_id, timestamp(bigint ms), app_version
- event_type: 'performance'|'action'|'error'|'navigation'|'resource'
- event_name: lcp, cls, inp, page_view, js_error, crash, fetch 등
- payload(JSON): $.value, $.rating, $.message, $.stack, $.url, $.duration
- context(JSON): $.url, $.screen_name, $.device.os, $.device.browser
- 파티션: platform, year, month, day, hour

## Lambda 로그 그룹
- /aws/lambda/${PROJECT_NAME}-ingest
- /aws/lambda/${PROJECT_NAME}-transform
- /aws/lambda/${PROJECT_NAME}-authorizer

## 도구 사용 규칙 (중요!)
1. **한 번에 최대 2개 도구만 사용하세요.** 모든 도구를 한꺼번에 호출하지 마세요.
2. 첫 라운드에서 핵심 도구로 데이터를 확인하고, 부족하면 다음 라운드에서 추가 도구를 사용하세요.
3. 질문과 무관한 도구는 사용하지 마세요.

## 질문별 도구 선택 가이드
| 질문 유형 | 첫 라운드 | 필요시 추가 |
|-----------|-----------|------------|
| 에러 분석 | SQL (에러 집계) | CWLOGS (Lambda 로그) |
| 성능 분석 | SQL (CWV/latency) | METRICS (인프라 지표) |
| 인프라 상태 | ALARM | METRICS (드릴다운) |
| 스키마 확인 | GLUE | - |
| Lambda 로그 | CWLOGS | SQL (연관 이벤트) |
| 리포트 발송 | SQL (데이터 수집) | SNS (발송) |
| 대시보드 기록 | SQL (분석) | GRAFANA (어노테이션) |

## 응답 형식
- 항상 한국어
- 결과를 마크다운 표로 정리
- 핵심 인사이트 2-3줄 요약
- 개선 제안 (있으면)`;

// ─── 도구 실행 ──────────────────────────────────────────────────────────────

async function queryAthena(sql: string, sessionId?: string): Promise<string> {
  try {
    const resp = await lambdaClient.send(new InvokeCommand({
      FunctionName: ATHENA_LAMBDA,
      Payload: Buffer.from(JSON.stringify({ input: { sql, session_id: sessionId } })),
    }));
    return new TextDecoder().decode(resp.Payload);
  } catch (e) { return JSON.stringify({ error: `Athena: ${e}` }); }
}

async function searchLogs(p: { logGroup: string; pattern: string; minutes?: number }): Promise<string> {
  try {
    const resp = await cwLogs.send(new FilterLogEventsCommand({
      logGroupName: p.logGroup, filterPattern: p.pattern,
      startTime: Date.now() - (p.minutes || 30) * 60000, limit: 20,
    }));
    const events = (resp.events || []).map(e => ({ ts: new Date(e.timestamp || 0).toISOString(), msg: (e.message || '').slice(0, 500) }));
    return JSON.stringify({ count: events.length, events });
  } catch (e) { return JSON.stringify({ error: `Logs: ${e}` }); }
}

async function getMetrics(p: { namespace: string; metricName: string; dimensions?: string; minutes?: number; stat?: string }): Promise<string> {
  try {
    const dims = p.dimensions ? p.dimensions.split(',').map(d => { const [k,v] = d.trim().split('='); return { Name: k, Value: v }; }) : [];
    const mins = p.minutes || 60;
    const stat = p.stat || 'Average';
    const resp = await cw.send(new GetMetricStatisticsCommand({
      Namespace: p.namespace, MetricName: p.metricName, Dimensions: dims,
      StartTime: new Date(Date.now() - mins * 60000), EndTime: new Date(),
      Period: Math.max(60, Math.floor(mins * 3)), Statistics: [stat as any],
    }));
    const pts = (resp.Datapoints || []).sort((a,b) => (a.Timestamp?.getTime()||0) - (b.Timestamp?.getTime()||0))
      .map(pt => ({ time: pt.Timestamp?.toISOString(), value: (pt as any)[stat] || 0 }));
    return JSON.stringify({ metric: `${p.namespace}/${p.metricName}`, datapoints: pts });
  } catch (e) { return JSON.stringify({ error: `Metrics: ${e}` }); }
}

async function describeAlarms(p: { stateFilter?: string; prefix?: string }): Promise<string> {
  try {
    const resp = await cw.send(new DescribeAlarmsCommand({
      StateValue: p.stateFilter as any || undefined, AlarmNamePrefix: p.prefix || undefined, MaxRecords: 20,
    }));
    const alarms = (resp.MetricAlarms || []).map(a => ({
      name: a.AlarmName, state: a.StateValue, reason: (a.StateReason||'').slice(0,200),
      metric: `${a.Namespace}/${a.MetricName}`, updated: a.StateUpdatedTimestamp?.toISOString(),
    }));
    return JSON.stringify({ count: alarms.length, alarms });
  } catch (e) { return JSON.stringify({ error: `Alarms: ${e}` }); }
}

async function getTableSchema(p: { table: string; database?: string }): Promise<string> {
  try {
    const resp = await glue.send(new GetTableCommand({ DatabaseName: p.database || 'rum_pipeline_db', Name: p.table }));
    const t = resp.Table;
    return JSON.stringify({
      table: p.table,
      columns: (t?.StorageDescriptor?.Columns || []).map(c => ({ name: c.Name, type: c.Type })),
      partitions: (t?.PartitionKeys || []).map(pk => ({ name: pk.Name, type: pk.Type })),
    });
  } catch (e) { return JSON.stringify({ error: `Glue: ${e}` }); }
}

async function createAnnotation(p: { text: string; tags?: string }): Promise<string> {
  if (!GRAFANA_URL || !GRAFANA_API_KEY) return JSON.stringify({ error: 'GRAFANA 미설정' });
  try {
    const resp = await fetch(`${GRAFANA_URL}/api/annotations`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${GRAFANA_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: p.text, tags: (p.tags || 'agent').split(','), time: Date.now() }),
    });
    return await resp.text();
  } catch (e) { return JSON.stringify({ error: `Grafana: ${e}` }); }
}

async function publishSns(p: { subject?: string; message: string }): Promise<string> {
  if (!SNS_TOPIC_ARN) return JSON.stringify({ error: 'SNS_TOPIC_ARN 미설정' });
  try {
    const resp = await sns.send(new PublishCommand({
      TopicArn: SNS_TOPIC_ARN, Subject: (p.subject || 'RUM 리포트').slice(0, 100), Message: p.message.slice(0, 262144),
    }));
    return JSON.stringify({ messageId: resp.MessageId, status: '발송 완료' });
  } catch (e) { return JSON.stringify({ error: `SNS: ${e}` }); }
}

// ─── 태그 추출 및 라우팅 ────────────────────────────────────────────────────

type ToolTag = { type: string; content: string };

function extractToolTags(text: string): ToolTag[] {
  const tags: ToolTag[] = [];
  for (const t of ['SQL','CWLOGS','METRICS','ALARM','GLUE','GRAFANA','SNS']) {
    for (const m of text.matchAll(new RegExp(`<${t}>([\\s\\S]*?)</${t}>`, 'gi'))) {
      tags.push({ type: t, content: m[1].trim() });
    }
  }
  return tags;
}

async function runTool(tag: ToolTag, sid?: string): Promise<{ label: string; result: string }> {
  const handlers: Record<string, () => Promise<string>> = {
    SQL: () => queryAthena(tag.content, sid),
    CWLOGS: () => searchLogs(JSON.parse(tag.content)),
    METRICS: () => getMetrics(JSON.parse(tag.content)),
    ALARM: () => describeAlarms(JSON.parse(tag.content)),
    GLUE: () => getTableSchema(JSON.parse(tag.content)),
    GRAFANA: () => createAnnotation(JSON.parse(tag.content)),
    SNS: () => publishSns(JSON.parse(tag.content)),
  };
  const label = { SQL:'Athena', CWLOGS:'CW Logs', METRICS:'CW Metrics', ALARM:'Alarms', GLUE:'Glue', GRAFANA:'Grafana', SNS:'SNS' }[tag.type] || tag.type;
  return { label, result: await (handlers[tag.type] || (() => Promise.resolve('{"error":"unknown"}')))() };
}

function stripTags(text: string): string {
  let out = text;
  for (const t of ['SQL','CWLOGS','METRICS','ALARM','GLUE','GRAFANA','SNS']) {
    out = out.replace(new RegExp(`<${t}>[\\s\\S]*?</${t}>`, 'gi'), '');
  }
  return out.trim();
}

// ─── Bedrock ────────────────────────────────────────────────────────────────

async function callBedrock(messages: Array<{role: string; content: string}>): Promise<string> {
  const { BedrockRuntimeClient, InvokeModelCommand } = await import('@aws-sdk/client-bedrock-runtime');
  const bedrock = new BedrockRuntimeClient({ region: REGION });
  const resp = await bedrock.send(new InvokeModelCommand({
    modelId: BEDROCK_MODEL, contentType: 'application/json', accept: 'application/json',
    body: JSON.stringify({ anthropic_version: 'bedrock-2023-05-31', max_tokens: 4096, system: SYSTEM_PROMPT,
      messages: messages.map(m => ({ role: m.role, content: m.content })) }),
  }));
  return JSON.parse(new TextDecoder().decode(resp.body)).content?.[0]?.text || '';
}

// ─── POST Handler ───────────────────────────────────────────────────────────

export async function POST(request: NextRequest) {
  const userSub = request.headers.get('x-user-sub') || 'anonymous';
  const { prompt } = await request.json();
  if (!prompt) return new Response(JSON.stringify({ error: 'prompt required' }), { status: 400 });

  const sessionId = userSub;
  const enc = new TextEncoder();

  const stream = new ReadableStream({
    async start(ctrl) {
      const send = (d: object) => ctrl.enqueue(enc.encode(`data: ${JSON.stringify(d)}\n\n`));
      let hb: ReturnType<typeof setInterval> | null = null;
      const startHb = () => { hb = setInterval(() => ctrl.enqueue(enc.encode(`: heartbeat\n\n`)), 15000); };
      const stopHb = () => { if (hb) { clearInterval(hb); hb = null; } };

      try {
        send({ type: 'start' });
        send({ type: 'chunk', content: '\uD83D\uDD0D 분석 중... 리포트를 생성중입니다.\n\n' });
        const msgs: Array<{role: string; content: string}> = [{ role: 'user', content: prompt }];

        startHb(); const r1 = await callBedrock(msgs); stopHb();
        const t1 = extractToolTags(r1);

        if (!t1.length) {
          for (const c of (r1.match(/[\s\S]{1,30}/g) || [r1])) { send({ type:'chunk', content: c }); await new Promise(r=>setTimeout(r,5)); }
          send({ type: 'done' }); ctrl.close(); return;
        }

        send({ type: 'chunk', content: '\uD83D\uDCCA 데이터를 조회하고 있습니다...\n\n' });
        let results = '';
        for (const tag of t1) {
          const toolLabel = { SQL:'\uD83D\uDCCA Athena', CWLOGS:'\uD83D\uDCCB CW Logs', METRICS:'\uD83D\uDCC8 Metrics', ALARM:'\uD83D\uDD14 Alarms', GLUE:'\uD83D\uDDC2 Glue', GRAFANA:'\uD83D\uDCCA Grafana', SNS:'\uD83D\uDCE8 SNS' }[tag.type] || tag.type;
          send({ type: 'chunk', content: `${toolLabel} 분석 중... 리포트를 생성중입니다.\n\n` });
          startHb(); const { label, result } = await runTool(tag, sessionId); stopHb();
          try {
            const p = JSON.parse(result);
            const cnt = p.rowCount || p.count || p.datapoints?.length || '';
            if (p.error) { results += `[${label}] 실패: ${p.error}\n`; send({ type:'chunk', content: `\u26A0\uFE0F ${label}: ${p.error}\n\n` }); }
            else { results += `[${label}]${cnt?` (${cnt}건)`:''}: ${JSON.stringify(p,null,2)}\n\n`; send({ type:'chunk', content: `\u2705 ${label} ${cnt?`${cnt}건 `:''}완료\n\n` }); }
          } catch { results += `${result}\n`; }
        }

        msgs.push({ role: 'assistant', content: r1 });
        msgs.push({ role: 'user', content: `도구 결과입니다. 분석해주세요. 추가 필요시 도구 태그 사용.\n\n${results}` });

        for (let rd = 2; rd <= 4; rd++) {
          send({ type: 'chunk', content: '\uD83E\uDD16 분석 중... 리포트를 생성중입니다.\n\n---\n\n' });
          startHb(); const rr = await callBedrock(msgs); stopHb();
          const mt = extractToolTags(rr);

          if (!mt.length || rd > 3) {
            for (const c of (stripTags(rr).match(/[\s\S]{1,30}/g) || [stripTags(rr)])) { send({ type:'chunk', content: c }); await new Promise(r=>setTimeout(r,5)); }
            break;
          }

          send({ type: 'chunk', content: '\uD83D\uDCCA 추가 조회...\n\n' });
          let mr = '';
          for (const tag of mt) {
            startHb(); const { label, result } = await runTool(tag, sessionId); stopHb();
            try { const p = JSON.parse(result); mr += p.error ? `[${label}] 실패: ${p.error}\n` : `[${label}]: ${JSON.stringify(p,null,2)}\n\n`; send({ type:'chunk', content: `\u2705 ${label} 완료\n\n` }); }
            catch { mr += `${result}\n`; }
          }
          msgs.push({ role: 'assistant', content: rr });
          msgs.push({ role: 'user', content: `추가 결과. 최종 분석을 마크다운으로.\n\n${mr}` });
        }
        send({ type: 'done' });
      } catch (e: unknown) {
        send({ type: 'error', content: e instanceof Error ? e.message : 'Unknown error' });
      } finally { stopHb(); ctrl.close(); }
    },
  });

  return new Response(stream, { headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive' } });
}
