import { generateSession } from './session';
import { generateEvents } from './generator';
import { pickScenario } from './scenarios';

const ENDPOINT = process.env.RUM_API_ENDPOINT ?? '';
const API_KEY = process.env.RUM_API_KEY ?? '';
const EVENTS_PER_BATCH = parseInt(process.env.EVENTS_PER_BATCH ?? '100', 10);
const CONCURRENT_SESSIONS = parseInt(process.env.CONCURRENT_SESSIONS ?? '10', 10);

if (!ENDPOINT || !API_KEY) {
  console.error('ERROR: RUM_API_ENDPOINT and RUM_API_KEY are required');
  process.exit(1);
}

async function postBatch(events: object[]): Promise<void> {
  const res = await fetch(`${ENDPOINT}/v1/events`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-api-key': API_KEY },
    body: JSON.stringify(events),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
}

async function runSession(): Promise<{ sent: number; scenario: string }> {
  const session = generateSession();
  const scenario = pickScenario();
  const events = generateEvents(session, EVENTS_PER_BATCH, scenario);
  await postBatch(events);
  return { sent: events.length, scenario: scenario.name };
}

async function main(): Promise<void> {
  console.log(`[rum-simulator] Starting: ${CONCURRENT_SESSIONS} sessions x ${EVENTS_PER_BATCH} events`);
  console.log(`[rum-simulator] Endpoint: ${ENDPOINT}`);

  const results = await Promise.allSettled(
    Array.from({ length: CONCURRENT_SESSIONS }, () => runSession())
  );

  let totalSent = 0;
  let failed = 0;
  for (const r of results) {
    if (r.status === 'fulfilled') {
      totalSent += r.value.sent;
      console.log(`  [ok] scenario=${r.value.scenario} sent=${r.value.sent}`);
    } else {
      failed++;
      console.error(`  [err] ${r.reason}`);
    }
  }

  console.log(`[rum-simulator] Done: sent=${totalSent} failed=${failed}/${CONCURRENT_SESSIONS}`);
  if (failed === CONCURRENT_SESSIONS) process.exit(1);
}

main().catch((e) => { console.error(e); process.exit(1); });
