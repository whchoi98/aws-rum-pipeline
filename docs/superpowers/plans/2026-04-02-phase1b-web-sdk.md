# Phase 1b: Web SDK + Simulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a lightweight TypeScript RUM SDK and Node.js traffic simulator for the deployed RUM pipeline.

**Architecture:** npm package with modular collectors, event buffer with batch transport, and a Docker-based simulator generating realistic RUM events.

**Tech Stack:** TypeScript, esbuild, vitest, web-vitals, Node.js, Docker, K8s CronJob

**Spec:** `docs/superpowers/specs/2026-04-02-phase1b-web-sdk-design.md`

---

## File Structure

```
sdk/
├── package.json
├── tsconfig.json
├── vitest.config.ts
├── esbuild.config.js
├── src/
│   ├── index.ts
│   ├── config.ts
│   ├── buffer.ts
│   ├── transport.ts
│   ├── collectors/
│   │   ├── web-vitals.ts
│   │   ├── error.ts
│   │   ├── navigation.ts
│   │   └── resource.ts
│   └── utils/
│       ├── id.ts
│       └── context.ts
└── tests/
    ├── buffer.test.ts
    ├── transport.test.ts
    ├── utils/
    │   ├── id.test.ts
    │   └── context.test.ts
    └── collectors/
        ├── error.test.ts
        └── navigation.test.ts

simulator/
├── package.json
├── tsconfig.json
├── Dockerfile
├── k8s/
│   └── cronjob.yaml
└── src/
    ├── index.ts
    ├── generator.ts
    ├── scenarios.ts
    └── session.ts
```

---

## Task 1: SDK Project Setup

- [ ] Create `sdk/package.json`

```json
{
  "name": "@myorg/rum-sdk",
  "version": "0.1.0",
  "main": "dist/index.cjs",
  "module": "dist/index.mjs",
  "browser": "dist/rum-sdk.min.js",
  "types": "dist/index.d.ts",
  "scripts": {
    "build": "node esbuild.config.js",
    "test": "vitest run",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "web-vitals": "^4.0.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "esbuild": "^0.21.0",
    "vitest": "^1.6.0",
    "jsdom": "^24.0.0",
    "@vitest/environment-jsdom": "^1.6.0"
  }
}
```

- [ ] Create `sdk/tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ESNext", "DOM"],
    "strict": true,
    "declaration": true,
    "declarationDir": "dist",
    "outDir": "dist",
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

- [ ] Create `sdk/vitest.config.ts`

```typescript
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'jsdom',
    globals: true,
  },
});
```

- [ ] Create `sdk/esbuild.config.js`

```javascript
const esbuild = require('esbuild');

const shared = { entryPoints: ['src/index.ts'], bundle: true, sourcemap: true };

Promise.all([
  esbuild.build({ ...shared, format: 'esm',  outfile: 'dist/index.mjs' }),
  esbuild.build({ ...shared, format: 'cjs',  outfile: 'dist/index.cjs' }),
  esbuild.build({ ...shared, format: 'iife', outfile: 'dist/rum-sdk.min.js',
    globalName: 'RumSDK', minify: true }),
]).catch(() => process.exit(1));
```

- [ ] Run `cd sdk && npm install` to verify setup
- [ ] **Commit:** `feat(rum-sdk): scaffold SDK project with TypeScript, esbuild, vitest`

---

## Task 2: Config + Utils (TDD)

### Tests first

- [ ] Create `sdk/tests/utils/id.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { generateId } from '../../src/utils/id';

describe('generateId', () => {
  it('returns a non-empty string', () => {
    expect(typeof generateId()).toBe('string');
    expect(generateId().length).toBeGreaterThan(0);
  });

  it('returns unique values', () => {
    expect(generateId()).not.toBe(generateId());
  });
});
```

- [ ] Create `sdk/tests/utils/context.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { getBrowserContext } from '../../src/utils/context';

describe('getBrowserContext', () => {
  it('returns url, device, and connection fields', () => {
    const ctx = getBrowserContext();
    expect(ctx).toHaveProperty('url');
    expect(ctx).toHaveProperty('device');
    expect(ctx.device).toHaveProperty('os');
    expect(ctx.device).toHaveProperty('browser');
    expect(ctx).toHaveProperty('connection');
  });
});
```

### Implementation

- [ ] Create `sdk/src/config.ts`

```typescript
export interface RumConfig {
  endpoint: string;
  apiKey: string;
  appVersion: string;
  sampleRate?: number;
  flushInterval?: number;
  maxBatchSize?: number;
  debug?: boolean;
}

export interface RumEvent {
  session_id: string;
  user_id: string;
  device_id: string;
  timestamp: number;
  platform: 'web';
  app_version: string;
  event_type: 'performance' | 'action' | 'error' | 'navigation' | 'resource';
  event_name: string;
  payload: Record<string, unknown>;
  context: {
    url: string;
    device: { os: string; browser: string };
    connection: { type: string; rtt: number };
  };
}
```

- [ ] Create `sdk/src/utils/id.ts`

```typescript
export function generateId(): string {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}
```

- [ ] Create `sdk/src/utils/context.ts`

```typescript
import type { RumEvent } from '../config';

type Context = RumEvent['context'];

export function getBrowserContext(): Context {
  const nav = navigator as Navigator & { connection?: { effectiveType?: string; rtt?: number } };
  const conn = nav.connection;
  return {
    url: location.pathname + location.search,
    device: {
      os: getOS(navigator.userAgent),
      browser: getBrowser(navigator.userAgent),
    },
    connection: {
      type: conn?.effectiveType ?? 'unknown',
      rtt: conn?.rtt ?? 0,
    },
  };
}

function getOS(ua: string): string {
  if (/Windows/.test(ua)) return 'Windows';
  if (/Mac OS X/.test(ua)) return 'macOS';
  if (/Android/.test(ua)) return 'Android';
  if (/iPhone|iPad/.test(ua)) return 'iOS';
  if (/Linux/.test(ua)) return 'Linux';
  return 'unknown';
}

function getBrowser(ua: string): string {
  if (/Edg\//.test(ua)) return 'Edge';
  if (/Chrome\//.test(ua)) return 'Chrome';
  if (/Firefox\//.test(ua)) return 'Firefox';
  if (/Safari\//.test(ua)) return 'Safari';
  return 'unknown';
}
```

- [ ] Run tests: `cd sdk && npx vitest run tests/utils/id.test.ts tests/utils/context.test.ts`
- [ ] **Commit:** `feat(rum-sdk): add RumConfig/RumEvent types and id/context utils`

---

## Task 3: EventBuffer (TDD)

### Test first

- [ ] Create `sdk/tests/buffer.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { EventBuffer } from '../src/buffer';
import type { RumEvent } from '../src/config';

const makeEvent = (n = 0): RumEvent => ({
  session_id: `s${n}`, user_id: 'anon', device_id: 'd1',
  timestamp: Date.now(), platform: 'web', app_version: '1.0.0',
  event_type: 'action', event_name: 'click', payload: {},
  context: { url: '/', device: { os: 'macOS', browser: 'Chrome' }, connection: { type: '4g', rtt: 50 } },
});

describe('EventBuffer', () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it('flushes when batch size is reached', async () => {
    const flush = vi.fn().mockResolvedValue(undefined);
    const buf = new EventBuffer({ maxBatchSize: 3, flushInterval: 30000, onFlush: flush });
    buf.add(makeEvent(1));
    buf.add(makeEvent(2));
    expect(flush).not.toHaveBeenCalled();
    buf.add(makeEvent(3));
    await Promise.resolve();
    expect(flush).toHaveBeenCalledWith(expect.arrayContaining([expect.objectContaining({ session_id: 's1' })]));
  });

  it('flushes on timer', async () => {
    const flush = vi.fn().mockResolvedValue(undefined);
    const buf = new EventBuffer({ maxBatchSize: 10, flushInterval: 5000, onFlush: flush });
    buf.add(makeEvent(1));
    vi.advanceTimersByTime(5000);
    await Promise.resolve();
    expect(flush).toHaveBeenCalled();
  });

  it('re-queues events on flush failure and caps at 500', async () => {
    const flush = vi.fn().mockRejectedValue(new Error('fail'));
    const buf = new EventBuffer({ maxBatchSize: 2, flushInterval: 30000, onFlush: flush });
    for (let i = 0; i < 510; i++) buf.add(makeEvent(i));
    await Promise.resolve();
    // Internal queue should not exceed 500
    expect(buf.size()).toBeLessThanOrEqual(500);
  });
});
```

### Implementation

- [ ] Create `sdk/src/buffer.ts`

```typescript
import type { RumEvent } from './config';

interface BufferOptions {
  maxBatchSize: number;
  flushInterval: number;
  onFlush: (events: RumEvent[]) => Promise<void>;
}

export class EventBuffer {
  private queue: RumEvent[] = [];
  private timer: ReturnType<typeof setInterval> | null = null;
  private readonly opts: BufferOptions;

  constructor(opts: BufferOptions) {
    this.opts = opts;
    this.timer = setInterval(() => this.flush(), opts.flushInterval);
  }

  add(event: RumEvent): void {
    this.queue.push(event);
    if (this.queue.length >= this.opts.maxBatchSize) {
      this.flush();
    }
  }

  async flush(): Promise<void> {
    if (this.queue.length === 0) return;
    const batch = this.queue.splice(0, this.opts.maxBatchSize);
    try {
      await this.opts.onFlush(batch);
    } catch {
      // Re-queue, capped at 500 (drop oldest)
      const combined = [...batch, ...this.queue];
      this.queue = combined.slice(-500);
    }
  }

  flushSync(sendBeacon: (events: RumEvent[]) => void): void {
    if (this.queue.length === 0) return;
    sendBeacon(this.queue.splice(0));
  }

  size(): number {
    return this.queue.length;
  }

  destroy(): void {
    if (this.timer) clearInterval(this.timer);
  }
}
```

- [ ] Run tests: `cd sdk && npx vitest run tests/buffer.test.ts`
- [ ] **Commit:** `feat(rum-sdk): add EventBuffer with batch size, timer flush, and overflow cap`

---

## Task 4: Transport (TDD)

### Test first

- [ ] Create `sdk/tests/transport.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { Transport } from '../src/transport';
import type { RumEvent } from '../src/config';

const events: RumEvent[] = [{
  session_id: 's1', user_id: 'anon', device_id: 'd1',
  timestamp: Date.now(), platform: 'web', app_version: '1.0.0',
  event_type: 'action', event_name: 'click', payload: {},
  context: { url: '/', device: { os: 'macOS', browser: 'Chrome' }, connection: { type: '4g', rtt: 50 } },
}];

describe('Transport', () => {
  beforeEach(() => { vi.restoreAllMocks(); });

  it('sends events successfully via fetch', async () => {
    const mockFetch = vi.fn().mockResolvedValue({ ok: true, status: 200 });
    vi.stubGlobal('fetch', mockFetch);
    const t = new Transport({ endpoint: 'https://api.example.com', apiKey: 'test-key' });
    await t.send(events);
    expect(mockFetch).toHaveBeenCalledOnce();
    const [url, opts] = mockFetch.mock.calls[0];
    expect(url).toBe('https://api.example.com/v1/events');
    expect(JSON.parse(opts.body)).toEqual(events);
  });

  it('retries on 5xx up to 3 times', async () => {
    const mockFetch = vi.fn().mockResolvedValue({ ok: false, status: 503 });
    vi.stubGlobal('fetch', mockFetch);
    const t = new Transport({ endpoint: 'https://api.example.com', apiKey: 'key', retryDelay: 0 });
    await expect(t.send(events)).rejects.toThrow();
    expect(mockFetch).toHaveBeenCalledTimes(3);
  });

  it('does not retry on 4xx', async () => {
    const mockFetch = vi.fn().mockResolvedValue({ ok: false, status: 400 });
    vi.stubGlobal('fetch', mockFetch);
    const t = new Transport({ endpoint: 'https://api.example.com', apiKey: 'key' });
    await expect(t.send(events)).rejects.toThrow();
    expect(mockFetch).toHaveBeenCalledTimes(1);
  });
});
```

### Implementation

- [ ] Create `sdk/src/transport.ts`

```typescript
import type { RumEvent } from './config';

interface TransportOptions {
  endpoint: string;
  apiKey: string;
  maxRetries?: number;
  retryDelay?: number; // base delay ms (for testing override)
}

export class Transport {
  private readonly opts: Required<TransportOptions>;

  constructor(opts: TransportOptions) {
    this.opts = { maxRetries: 3, retryDelay: 1000, ...opts };
  }

  async send(events: RumEvent[]): Promise<void> {
    const { endpoint, apiKey, maxRetries, retryDelay } = this.opts;
    const url = `${endpoint}/v1/events`;
    const body = JSON.stringify(events);
    const headers = { 'Content-Type': 'application/json', 'x-api-key': apiKey };

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      const res = await fetch(url, { method: 'POST', headers, body });
      if (res.ok) return;
      if (res.status < 500) throw new Error(`HTTP ${res.status}: non-retryable`);
      if (attempt === maxRetries) throw new Error(`HTTP ${res.status}: max retries exceeded`);
      await sleep(retryDelay * 2 ** (attempt - 1));
    }
  }

  sendBeacon(events: RumEvent[], endpoint: string, apiKey: string): boolean {
    const blob = new Blob([JSON.stringify(events)], { type: 'application/json' });
    // Note: sendBeacon cannot set custom headers; API key sent via query param fallback
    return navigator.sendBeacon(`${endpoint}/v1/events?apiKey=${apiKey}`, blob);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
```

- [ ] Run tests: `cd sdk && npx vitest run tests/transport.test.ts`
- [ ] **Commit:** `feat(rum-sdk): add Transport with fetch, exponential backoff retry, sendBeacon`

---

## Task 5: Error + Navigation Collectors (TDD)

### Tests first

- [ ] Create `sdk/tests/collectors/error.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { ErrorCollector } from '../../src/collectors/error';
import type { RumEvent } from '../../src/config';

describe('ErrorCollector', () => {
  let captured: RumEvent[] = [];
  let collector: ErrorCollector;

  beforeEach(() => {
    captured = [];
    collector = new ErrorCollector({
      sessionId: 's1', deviceId: 'd1', appVersion: '1.0.0',
      onEvent: (e) => captured.push(e),
    });
  });

  afterEach(() => { collector.destroy(); });

  it('captures window error events', () => {
    window.dispatchEvent(new ErrorEvent('error', {
      message: 'TypeError: x is not defined',
      filename: 'app.js', lineno: 10, colno: 5,
      error: new Error('x is not defined'),
    }));
    expect(captured).toHaveLength(1);
    expect(captured[0].event_type).toBe('error');
    expect(captured[0].event_name).toBe('js_error');
    expect(captured[0].payload).toMatchObject({ message: 'TypeError: x is not defined' });
  });

  it('captures unhandledrejection events', () => {
    const event = new PromiseRejectionEvent('unhandledrejection', {
      promise: Promise.resolve(),
      reason: new Error('async failure'),
    });
    window.dispatchEvent(event);
    expect(captured).toHaveLength(1);
    expect(captured[0].event_name).toBe('unhandled_rejection');
  });

  it('ignores errors from the SDK itself', () => {
    window.dispatchEvent(new ErrorEvent('error', {
      message: 'RumSDK internal error',
      filename: 'rum-sdk.min.js',
    }));
    expect(captured).toHaveLength(0);
  });
});
```

- [ ] Create `sdk/tests/collectors/navigation.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { NavigationCollector } from '../../src/collectors/navigation';
import type { RumEvent } from '../../src/config';

describe('NavigationCollector', () => {
  let captured: RumEvent[] = [];
  let collector: NavigationCollector;

  beforeEach(() => {
    captured = [];
    collector = new NavigationCollector({
      sessionId: 's1', deviceId: 'd1', appVersion: '1.0.0',
      onEvent: (e) => captured.push(e),
    });
  });

  afterEach(() => { collector.destroy(); });

  it('emits page_view on init', () => {
    expect(captured.some((e) => e.event_name === 'page_view')).toBe(true);
  });

  it('detects route_change via pushState', () => {
    history.pushState({}, '', '/new-route');
    expect(captured.some((e) => e.event_name === 'route_change')).toBe(true);
    const rc = captured.find((e) => e.event_name === 'route_change')!;
    expect((rc.payload as { url: string }).url).toContain('/new-route');
  });
});
```

### Implementation

- [ ] Create `sdk/src/collectors/error.ts`

```typescript
import type { RumEvent } from '../config';
import { getBrowserContext } from '../utils/context';

interface CollectorOptions {
  sessionId: string;
  deviceId: string;
  appVersion: string;
  onEvent: (e: RumEvent) => void;
}

const SDK_FILENAMES = ['rum-sdk.min.js', 'rum-sdk.js', 'index.mjs', 'index.cjs'];

export class ErrorCollector {
  private readonly opts: CollectorOptions;
  private readonly onError: (e: ErrorEvent) => void;
  private readonly onRejection: (e: PromiseRejectionEvent) => void;

  constructor(opts: CollectorOptions) {
    this.opts = opts;

    this.onError = (e: ErrorEvent) => {
      if (SDK_FILENAMES.some((f) => e.filename?.includes(f))) return;
      opts.onEvent(this.makeEvent('js_error', {
        message: e.message,
        stack: e.error?.stack?.slice(0, 1000) ?? '',
        filename: e.filename, lineno: e.lineno, colno: e.colno,
      }));
    };

    this.onRejection = (e: PromiseRejectionEvent) => {
      const err = e.reason instanceof Error ? e.reason : new Error(String(e.reason));
      opts.onEvent(this.makeEvent('unhandled_rejection', {
        message: err.message,
        stack: err.stack?.slice(0, 1000) ?? '',
      }));
    };

    window.addEventListener('error', this.onError);
    window.addEventListener('unhandledrejection', this.onRejection);
  }

  private makeEvent(name: string, payload: Record<string, unknown>): RumEvent {
    const { sessionId, deviceId, appVersion } = this.opts;
    return {
      session_id: sessionId, user_id: 'anonymous', device_id: deviceId,
      timestamp: Date.now(), platform: 'web', app_version: appVersion,
      event_type: 'error', event_name: name, payload,
      context: getBrowserContext(),
    };
  }

  destroy(): void {
    window.removeEventListener('error', this.onError);
    window.removeEventListener('unhandledrejection', this.onRejection);
  }
}
```

- [ ] Create `sdk/src/collectors/navigation.ts`

```typescript
import type { RumEvent } from '../config';
import { getBrowserContext } from '../utils/context';

interface CollectorOptions {
  sessionId: string;
  deviceId: string;
  appVersion: string;
  onEvent: (e: RumEvent) => void;
}

export class NavigationCollector {
  private readonly opts: CollectorOptions;
  private readonly onPopState: () => void;
  private readonly origPushState: typeof history.pushState;
  private readonly origReplaceState: typeof history.replaceState;

  constructor(opts: CollectorOptions) {
    this.opts = opts;

    // Emit initial page_view
    opts.onEvent(this.makeEvent('page_view', { url: location.href, referrer: document.referrer, duration: 0 }));

    // Wrap History API
    this.origPushState = history.pushState.bind(history);
    this.origReplaceState = history.replaceState.bind(history);

    history.pushState = (...args) => {
      this.origPushState(...args);
      opts.onEvent(this.makeEvent('route_change', { url: location.href, referrer: '', duration: 0 }));
    };

    history.replaceState = (...args) => {
      this.origReplaceState(...args);
      opts.onEvent(this.makeEvent('route_change', { url: location.href, referrer: '', duration: 0 }));
    };

    this.onPopState = () => {
      opts.onEvent(this.makeEvent('route_change', { url: location.href, referrer: '', duration: 0 }));
    };
    window.addEventListener('popstate', this.onPopState);
  }

  private makeEvent(name: string, payload: Record<string, unknown>): RumEvent {
    const { sessionId, deviceId, appVersion } = this.opts;
    return {
      session_id: sessionId, user_id: 'anonymous', device_id: deviceId,
      timestamp: Date.now(), platform: 'web', app_version: appVersion,
      event_type: 'navigation', event_name: name, payload,
      context: getBrowserContext(),
    };
  }

  destroy(): void {
    history.pushState = this.origPushState;
    history.replaceState = this.origReplaceState;
    window.removeEventListener('popstate', this.onPopState);
  }
}
```

- [ ] Run tests: `cd sdk && npx vitest run tests/collectors/error.test.ts tests/collectors/navigation.test.ts`
- [ ] **Commit:** `feat(rum-sdk): add ErrorCollector and NavigationCollector with TDD`

---

## Task 6: WebVitals + Resource Collectors

- [ ] Implement `sdk/src/collectors/web-vitals.ts`

```typescript
import { onLCP, onCLS, onINP } from 'web-vitals';
import type { RumEvent } from '../config';
import { getBrowserContext } from '../utils/context';

interface CollectorOptions {
  sessionId: string;
  deviceId: string;
  appVersion: string;
  onEvent: (e: RumEvent) => void;
}

export class WebVitalsCollector {
  constructor(opts: CollectorOptions) {
    const emit = (name: string, value: number, rating: string, navigationType?: string) => {
      const { sessionId, deviceId, appVersion } = opts;
      opts.onEvent({
        session_id: sessionId, user_id: 'anonymous', device_id: deviceId,
        timestamp: Date.now(), platform: 'web', app_version: appVersion,
        event_type: 'performance', event_name: name,
        payload: { value, rating, navigationType: navigationType ?? 'navigate' },
        context: getBrowserContext(),
      });
    };

    onLCP((m) => emit('lcp', m.value, m.rating, m.navigationType));
    onCLS((m) => emit('cls', m.value, m.rating, m.navigationType));
    onINP((m) => emit('inp', m.value, m.rating, m.navigationType));
  }
}
```

- [ ] Implement `sdk/src/collectors/resource.ts`

```typescript
import type { RumEvent } from '../config';
import { getBrowserContext } from '../utils/context';

interface CollectorOptions {
  sessionId: string;
  deviceId: string;
  appVersion: string;
  onEvent: (e: RumEvent) => void;
}

export class ResourceCollector {
  private observer: PerformanceObserver | null = null;

  constructor(opts: CollectorOptions) {
    if (typeof PerformanceObserver === 'undefined') return;

    this.observer = new PerformanceObserver((list) => {
      for (const entry of list.getEntries() as PerformanceResourceTiming[]) {
        if (!['xmlhttprequest', 'fetch'].includes(entry.initiatorType)) continue;
        const { sessionId, deviceId, appVersion } = opts;
        opts.onEvent({
          session_id: sessionId, user_id: 'anonymous', device_id: deviceId,
          timestamp: Date.now(), platform: 'web', app_version: appVersion,
          event_type: 'resource',
          event_name: entry.initiatorType === 'fetch' ? 'fetch' : 'xhr',
          payload: {
            url: entry.name,
            duration: Math.round(entry.duration),
            transferSize: entry.transferSize,
          },
          context: getBrowserContext(),
        });
      }
    });
    this.observer.observe({ type: 'resource', buffered: true });
  }

  destroy(): void {
    this.observer?.disconnect();
  }
}
```

- [ ] Note: These rely on browser APIs (`PerformanceObserver`, `web-vitals`). Tests use minimal mocks — no vitest environment required for web-vitals since it fires via callbacks.
- [ ] **Commit:** `feat(rum-sdk): add WebVitalsCollector (LCP/CLS/INP) and ResourceCollector`

---

## Task 7: SDK Entry Point + Build

- [ ] Implement `sdk/src/index.ts`

```typescript
import type { RumConfig, RumEvent } from './config';
import { EventBuffer } from './buffer';
import { Transport } from './transport';
import { generateId } from './utils/id';
import { ErrorCollector } from './collectors/error';
import { NavigationCollector } from './collectors/navigation';
import { WebVitalsCollector } from './collectors/web-vitals';
import { ResourceCollector } from './collectors/resource';

let _instance: RumSDKInstance | null = null;

interface RumSDKInstance {
  buffer: EventBuffer;
  transport: Transport;
  collectors: { destroy(): void }[];
  sessionId: string;
  deviceId: string;
  userId: string;
}

export class RumSDK {
  static init(config: RumConfig): void {
    if (_instance) return;
    if (Math.random() > (config.sampleRate ?? 1.0)) return;

    const sessionId = generateId();
    const deviceId = generateId();
    const transport = new Transport({ endpoint: config.endpoint, apiKey: config.apiKey });

    const buffer = new EventBuffer({
      maxBatchSize: config.maxBatchSize ?? 10,
      flushInterval: config.flushInterval ?? 30000,
      onFlush: (events) => transport.send(events),
    });

    const collectorOpts = {
      sessionId, deviceId, appVersion: config.appVersion,
      onEvent: (e: RumEvent) => buffer.add(e),
    };

    const collectors = [
      new ErrorCollector(collectorOpts),
      new NavigationCollector(collectorOpts),
      new WebVitalsCollector(collectorOpts),
      new ResourceCollector(collectorOpts),
    ];

    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') {
        buffer.flushSync((events) => transport.sendBeacon(events, config.endpoint, config.apiKey));
      }
    });

    _instance = { buffer, transport, collectors, sessionId, deviceId, userId: 'anonymous' };
  }

  static destroy(): void {
    if (!_instance) return;
    _instance.buffer.flush();
    _instance.buffer.destroy();
    _instance.collectors.forEach((c) => c.destroy());
    _instance = null;
  }

  static setUser(userId: string): void {
    if (_instance) _instance.userId = userId;
  }

  static addCustomEvent(name: string, payload: object): void {
    if (!_instance) return;
    _instance.buffer.add({
      session_id: _instance.sessionId, user_id: _instance.userId,
      device_id: _instance.deviceId, timestamp: Date.now(),
      platform: 'web', app_version: '', event_type: 'action',
      event_name: name, payload: payload as Record<string, unknown>,
      context: { url: location.pathname, device: { os: '', browser: '' }, connection: { type: '', rtt: 0 } },
    });
  }
}
```

- [ ] Update `sdk/esbuild.config.js` to set `external: []` and confirm `web-vitals` is bundled
- [ ] Run build: `cd sdk && npm run build`
- [ ] Check IIFE bundle size: `ls -lh sdk/dist/rum-sdk.min.js` — must be < 15KB uncompressed
- [ ] **Commit:** `feat(rum-sdk): wire SDK entry point, all collectors, buffer, transport`

---

## Task 8: Simulator — Event Generator + Scenarios

- [ ] Create `simulator/package.json`

```json
{
  "name": "rum-simulator",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "start": "npx tsx src/index.ts",
    "test": "vitest run"
  },
  "dependencies": {
    "tsx": "^4.7.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "vitest": "^1.6.0",
    "@types/node": "^20.0.0"
  }
}
```

- [ ] Create `simulator/tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "skipLibCheck": true
  },
  "include": ["src", "tests"]
}
```

- [ ] Implement `simulator/src/session.ts`

```typescript
import { randomUUID } from 'crypto';

export interface SessionContext {
  session_id: string;
  user_id: string;
  device_id: string;
  platform: 'web';
  app_version: string;
  context: {
    url: string;
    device: { os: string; browser: string };
    connection: { type: string; rtt: number };
  };
}

const OS = ['macOS', 'Windows', 'Android', 'iOS', 'Linux'];
const BROWSERS = ['Chrome', 'Firefox', 'Safari', 'Edge'];
const CONNECTIONS = ['4g', '3g', 'wifi'];
const PAGES = ['/', '/products', '/cart', '/checkout', '/account'];

export function generateSession(appVersion = '2.1.0'): SessionContext {
  return {
    session_id: randomUUID(),
    user_id: Math.random() < 0.3 ? 'anonymous' : `user_${randomUUID().slice(0, 8)}`,
    device_id: randomUUID(),
    platform: 'web',
    app_version: appVersion,
    context: {
      url: PAGES[Math.floor(Math.random() * PAGES.length)],
      device: {
        os: OS[Math.floor(Math.random() * OS.length)],
        browser: BROWSERS[Math.floor(Math.random() * BROWSERS.length)],
      },
      connection: {
        type: CONNECTIONS[Math.floor(Math.random() * CONNECTIONS.length)],
        rtt: Math.floor(Math.random() * 200),
      },
    },
  };
}
```

- [ ] Implement `simulator/src/generator.ts`

```typescript
import type { SessionContext } from './session';
import type { ScenarioConfig } from './scenarios';

export interface RumEvent {
  session_id: string;
  user_id: string;
  device_id: string;
  timestamp: number;
  platform: 'web';
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

function getEventName(type: RumEvent['event_type']): string {
  const names: Record<RumEvent['event_type'], string[]> = {
    performance: ['lcp', 'cls', 'inp'],
    navigation: Math.random() < 0.8 ? ['page_view'] : ['route_change'],
    resource: Math.random() < 0.6 ? ['fetch'] : ['xhr'],
    error: Math.random() < 0.7 ? ['js_error'] : ['unhandled_rejection'],
    action: Math.random() < 0.8 ? ['click'] : ['scroll'],
  };
  const opts = names[type];
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
      event_name: getEventName(type),
      payload: makePayload(type, scenario),
      context: session.context,
    };
  });
}
```

- [ ] Implement `simulator/src/scenarios.ts`

```typescript
export interface ScenarioConfig {
  name: string;
  lcpMultiplier?: number;  // 1.0 = normal, 3.0 = slow
  errorRate?: number;      // fraction of error events that are "spiked"
}

export const scenarios: Record<string, ScenarioConfig> = {
  normal:     { name: 'normal',     lcpMultiplier: 1.0, errorRate: 0.05 },
  slowPage:   { name: 'slowPage',   lcpMultiplier: 3.0, errorRate: 0.08 },
  errorSpike: { name: 'errorSpike', lcpMultiplier: 1.2, errorRate: 0.80 },
};

export function pickScenario(): ScenarioConfig {
  const r = Math.random();
  if (r < 0.70) return scenarios.normal;
  if (r < 0.90) return scenarios.slowPage;
  return scenarios.errorSpike;
}
```

- [ ] Create `simulator/tests/generator.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { generateEvents } from '../src/generator';
import { generateSession } from '../src/session';
import { scenarios } from '../src/scenarios';

describe('generateEvents', () => {
  it('returns requested count', () => {
    const session = generateSession();
    const events = generateEvents(session, 100, scenarios.normal);
    expect(events).toHaveLength(100);
  });

  it('respects event type distribution roughly (±15%)', () => {
    const session = generateSession();
    const events = generateEvents(session, 1000, scenarios.normal);
    const counts = events.reduce((acc, e) => {
      acc[e.event_type] = (acc[e.event_type] ?? 0) + 1;
      return acc;
    }, {} as Record<string, number>);
    expect(counts.performance / 1000).toBeGreaterThan(0.15);
    expect(counts.performance / 1000).toBeLessThan(0.45);
    expect(counts.navigation / 1000).toBeGreaterThan(0.10);
    expect(counts.error / 1000).toBeGreaterThan(0.02);
  });

  it('all events have required fields', () => {
    const session = generateSession();
    const events = generateEvents(session, 10, scenarios.normal);
    for (const e of events) {
      expect(e).toHaveProperty('session_id');
      expect(e).toHaveProperty('timestamp');
      expect(e).toHaveProperty('event_type');
      expect(e).toHaveProperty('payload');
    }
  });
});
```

- [ ] Run tests: `cd simulator && npm install && npx vitest run`
- [ ] **Commit:** `feat(rum-simulator): add session generator, event generator, scenarios`

---

## Task 9: Simulator — Main + Docker + K8s

- [ ] Implement `simulator/src/index.ts`

```typescript
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
```

- [ ] Create `simulator/Dockerfile`

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY tsconfig.json ./
COPY src/ ./src/
CMD ["npx", "tsx", "src/index.ts"]
```

- [ ] Create `simulator/k8s/cronjob.yaml`

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: rum-simulator
  namespace: rum
spec:
  schedule: "*/5 * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: simulator
            image: ${ECR_REPO}/rum-simulator:latest
            env:
            - name: RUM_API_ENDPOINT
              value: "https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com"
            - name: EVENTS_PER_BATCH
              value: "100"
            - name: CONCURRENT_SESSIONS
              value: "10"
            - name: RUM_API_KEY
              valueFrom:
                secretKeyRef:
                  name: rum-api-key
                  key: api-key
            resources:
              requests:
                cpu: "100m"
                memory: "128Mi"
              limits:
                cpu: "200m"
                memory: "256Mi"
```

- [ ] Test locally against deployed API:

```bash
cd simulator && npm install
RUM_API_ENDPOINT=https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com \
RUM_API_KEY=<your-key> \
EVENTS_PER_BATCH=10 \
CONCURRENT_SESSIONS=2 \
npx tsx src/index.ts
```

- [ ] Verify response: expect `[rum-simulator] Done: sent=20 failed=0/2`
- [ ] **Commit:** `feat(rum-simulator): add main loop, Dockerfile, K8s CronJob`
