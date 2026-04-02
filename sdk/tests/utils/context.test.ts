import { describe, it, expect } from 'vitest';
import { getBrowserContext } from '../../src/utils/context';

describe('getBrowserContext', () => {
  it('returns url, device, and connection fields', () => {
    const ctx = getBrowserContext();
    expect(ctx).toHaveProperty('url');
    expect(ctx).toHaveProperty('device');
    expect(ctx.device).toHaveProperty('os');
    expect(ctx.device).toHaveProperty('browser');
    expect(ctx).toHaveProperty('connection');
  });
});
