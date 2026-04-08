import { NextRequest } from 'next/server';

const AGENT_URL = process.env.AGENT_URL || 'http://localhost:8080/invocations';
const AGENT_TIMEOUT = Number(process.env.AGENT_TIMEOUT || '180000'); // 180초

export async function POST(request: NextRequest) {
  const userSub = request.headers.get('x-user-sub') || 'anonymous';

  let body: { prompt?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid JSON' }), { status: 400 });
  }

  const { prompt } = body;
  if (!prompt) {
    return new Response(JSON.stringify({ error: 'prompt required' }), { status: 400 });
  }

  let agentResp: Response;
  try {
    agentResp = await fetch(AGENT_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt, session_id: userSub }),
      signal: AbortSignal.timeout(AGENT_TIMEOUT),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Agent unavailable';
    return new Response(JSON.stringify({ error: msg }), { status: 502 });
  }

  if (!agentResp.ok || !agentResp.body) {
    const text = await agentResp.text().catch(() => 'unknown error');
    return new Response(JSON.stringify({ error: text }), { status: agentResp.status || 502 });
  }

  return new Response(agentResp.body, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    },
  });
}
