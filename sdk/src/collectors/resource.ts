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
          payload: { url: entry.name, duration: Math.round(entry.duration), transferSize: entry.transferSize },
          context: getBrowserContext(),
        });
      }
    });
    this.observer.observe({ type: 'resource', buffered: true });
  }

  destroy(): void { this.observer?.disconnect(); }
}
