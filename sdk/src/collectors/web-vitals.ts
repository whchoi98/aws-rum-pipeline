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
