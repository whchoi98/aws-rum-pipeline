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
    expect(buf.size()).toBeLessThanOrEqual(500);
  });
});
