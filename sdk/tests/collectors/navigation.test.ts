import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { NavigationCollector } from '../../src/collectors/navigation';
import type { RumEvent } from '../../src/config';

describe('NavigationCollector', () => {
  let captured: RumEvent[] = [];
  let collector: NavigationCollector;

  beforeEach(() => {
    captured = [];
    collector = new NavigationCollector({
      sessionId: 's1', deviceId: 'd1', appVersion: '1.0.0',
      onEvent: (e) => captured.push(e),
    });
  });
  afterEach(() => { collector.destroy(); });

  it('emits page_view on init', () => {
    expect(captured.some((e) => e.event_name === 'page_view')).toBe(true);
  });

  it('detects route_change via pushState', () => {
    history.pushState({}, '', '/new-route');
    expect(captured.some((e) => e.event_name === 'route_change')).toBe(true);
    const rc = captured.find((e) => e.event_name === 'route_change')!;
    expect((rc.payload as { url: string }).url).toContain('/new-route');
  });
});
