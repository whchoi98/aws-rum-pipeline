import type { SessionContext } from './session';
import type { ScenarioConfig } from './scenarios';

export interface RumEvent {
  session_id: string;
  user_id: string;
  device_id: string;
  timestamp: number;
  platform: 'web' | 'ios' | 'android';
  app_version: string;
  event_type: 'performance' | 'action' | 'error' | 'navigation' | 'resource';
  event_name: string;
  payload: Record<string, unknown>;
  context: SessionContext['context'];
}

// Distribution: performance 30%, navigation 25%, resource 25%, error 10%, action 10%
const EVENT_TYPES: Array<[RumEvent['event_type'], number]> = [
  ['performance', 0.30],
  ['navigation', 0.25],
  ['resource',   0.25],
  ['error',      0.10],
  ['action',     0.10],
];

function pickType(): RumEvent['event_type'] {
  const r = Math.random();
  let acc = 0;
  for (const [type, weight] of EVENT_TYPES) {
    acc += weight;
    if (r < acc) return type;
  }
  return 'action';
}

function makePayload(type: RumEvent['event_type'], scenario: ScenarioConfig): Record<string, unknown> {
  switch (type) {
    case 'performance': {
      const ratings = ['good', 'needs-improvement', 'poor'];
      const rating = Math.random() < 0.7 ? 'good' : Math.random() < 0.67 ? 'needs-improvement' : 'poor';
      const base = scenario.lcpMultiplier ?? 1;
      return { value: Math.round(1200 * base + Math.random() * 3000 * base), rating, navigationType: 'navigate' };
    }
    case 'navigation':
      return { url: '/page_' + Math.floor(Math.random() * 20), referrer: '/', duration: Math.round(Math.random() * 2000) };
    case 'resource': {
      const status = Math.random() < 0.05 ? 404 : Math.random() < 0.02 ? 500 : 200;
      return { url: `/api/resource_${Math.floor(Math.random() * 50)}`, duration: Math.round(Math.random() * 500), transferSize: Math.round(Math.random() * 50000), status };
    }
    case 'error':
      return scenario.errorRate && Math.random() < scenario.errorRate
        ? { message: 'TypeError: Cannot read property of undefined', stack: 'Error\n  at app.js:42', filename: 'app.js', lineno: 42, colno: 5 }
        : { message: 'ReferenceError: variable is not defined', stack: '', filename: 'app.js', lineno: 10, colno: 1 };
    case 'action':
      return { element: 'button', label: `btn_${Math.floor(Math.random() * 10)}` };
  }
}

function getEventName(type: RumEvent['event_type'], platform: string): string {
  if (platform === 'ios' || platform === 'android') {
    const mobileNames: Record<RumEvent['event_type'], string[]> = {
      performance: ['app_start', 'screen_load', 'frame_drop'],
      navigation: ['screen_view', 'screen_transition'],
      resource: ['fetch', 'xhr'],
      error: platform === 'android' ? ['crash', 'anr', 'unhandled_exception'] : ['crash', 'oom', 'unhandled_exception'],
      action: ['tap', 'swipe', 'scroll'],
    };
    const opts = mobileNames[type];
    return opts[Math.floor(Math.random() * opts.length)];
  }
  const webNames: Record<RumEvent['event_type'], string[]> = {
    performance: ['lcp', 'cls', 'inp'],
    navigation: Math.random() < 0.8 ? ['page_view'] : ['route_change'],
    resource: Math.random() < 0.6 ? ['fetch'] : ['xhr'],
    error: Math.random() < 0.7 ? ['js_error'] : ['unhandled_rejection'],
    action: Math.random() < 0.8 ? ['click'] : ['scroll'],
  };
  const opts = webNames[type];
  return opts[Math.floor(Math.random() * opts.length)];
}

export function generateEvents(session: SessionContext, count: number, scenario: ScenarioConfig): RumEvent[] {
  return Array.from({ length: count }, () => {
    const type = pickType();
    return {
      session_id: session.session_id,
      user_id: session.user_id,
      device_id: session.device_id,
      timestamp: Date.now() - Math.floor(Math.random() * 60000),
      platform: session.platform,
      app_version: session.app_version,
      event_type: type,
      event_name: getEventName(type, session.platform),
      payload: makePayload(type, scenario),
      context: session.context,
    };
  });
}
