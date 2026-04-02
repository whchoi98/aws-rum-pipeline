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
