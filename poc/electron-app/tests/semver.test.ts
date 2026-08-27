import { describe, it, expect } from 'vitest';
import { compareSemver, gt, lte } from '../src/shared/semver';

describe('semver', () => {
  it('1.10.0 > 1.9.0 (not string compare)', () => {
    expect(compareSemver('1.10.0', '1.9.0')).toBe(1);
    expect(gt('1.10.0', '1.9.0')).toBe(true);
  });
  it('equal versions', () => {
    expect(compareSemver('1.0.0', '1.0.0')).toBe(0);
    expect(lte('1.0.0', '1.0.0')).toBe(true);
  });
  it('1.1.0 > 1.0.0', () => {
    expect(gt('1.1.0', '1.0.0')).toBe(true);
  });
  it('1.0.0 <= 1.1.0', () => {
    expect(lte('1.0.0', '1.1.0')).toBe(true);
  });
  it('throws on invalid', () => {
    expect(() => compareSemver('x', '1.0.0')).toThrow();
  });
});
