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
