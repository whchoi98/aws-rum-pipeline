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

export type { RumConfig, RumEvent } from './config';
