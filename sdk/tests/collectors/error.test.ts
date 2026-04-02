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
