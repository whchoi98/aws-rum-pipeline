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
