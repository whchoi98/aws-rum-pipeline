import type { RumEvent } from './config';

interface TransportOptions {
  endpoint: string;
  apiKey: string;
  maxRetries?: number;
  retryDelay?: number;
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
    return navigator.sendBeacon(`${endpoint}/v1/events?apiKey=${apiKey}`, blob);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}
