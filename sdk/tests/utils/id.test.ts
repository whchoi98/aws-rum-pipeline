import { describe, it, expect } from 'vitest';
import { generateId } from '../../src/utils/id';

describe('generateId', () => {
  it('returns a non-empty string', () => {
    expect(typeof generateId()).toBe('string');
    expect(generateId().length).toBeGreaterThan(0);
  });
  it('returns unique values', () => {
    expect(generateId()).not.toBe(generateId());
  });
});
