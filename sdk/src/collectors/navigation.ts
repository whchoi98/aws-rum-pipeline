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
    opts.onEvent(this.makeEvent('page_view', { url: location.href, referrer: document.referrer, duration: 0 }));
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
