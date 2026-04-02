import { describe, it, expect } from 'vitest';
import { generateEvents } from '../src/generator';
import { generateSession } from '../src/session';
import { scenarios } from '../src/scenarios';

describe('generateEvents', () => {
  it('returns requested count', () => {
    const session = generateSession();
    const events = generateEvents(session, 100, scenarios.normal);
    expect(events).toHaveLength(100);
  });

  it('respects event type distribution roughly (±15%)', () => {
    const session = generateSession();
    const events = generateEvents(session, 1000, scenarios.normal);
    const counts = events.reduce((acc, e) => {
      acc[e.event_type] = (acc[e.event_type] ?? 0) + 1;
      return acc;
    }, {} as Record<string, number>);
    expect(counts.performance / 1000).toBeGreaterThan(0.15);
    expect(counts.performance / 1000).toBeLessThan(0.45);
    expect(counts.navigation / 1000).toBeGreaterThan(0.10);
    expect(counts.error / 1000).toBeGreaterThan(0.02);
  });

  it('all events have required fields', () => {
    const session = generateSession();
    const events = generateEvents(session, 10, scenarios.normal);
    for (const e of events) {
      expect(e).toHaveProperty('session_id');
      expect(e).toHaveProperty('timestamp');
      expect(e).toHaveProperty('event_type');
      expect(e).toHaveProperty('payload');
    }
  });
});
