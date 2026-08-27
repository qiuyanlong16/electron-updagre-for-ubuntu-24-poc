import { describe, it, expect } from 'vitest';
import { detectUpgradeFromLastSeen } from '../src/shared/upgrade-detect';

describe('detectUpgradeFromLastSeen', () => {
  it('1: current > lastSeen -> returns lastSeen (upgrade)', () => {
    expect(detectUpgradeFromLastSeen('1.1.0', '1.0.0')).toBe('1.0.0');
  });
  it('2: current == lastSeen -> null (same version, no banner)', () => {
    expect(detectUpgradeFromLastSeen('1.0.0', '1.0.0')).toBeNull();
  });
  it('3: current < lastSeen -> null (downgrade, no banner)', () => {
    expect(detectUpgradeFromLastSeen('1.0.0', '1.1.0')).toBeNull();
  });
  it('4: semver not string compare (1.10.0 > 1.9.0)', () => {
    expect(detectUpgradeFromLastSeen('1.10.0', '1.9.0')).toBe('1.9.0');
  });
  it('5: no lastSeen (first run) -> null', () => {
    expect(detectUpgradeFromLastSeen('1.0.0', null)).toBeNull();
  });
  it('6: invalid lastSeen (banana) -> null (corrupt file, no crash)', () => {
    expect(detectUpgradeFromLastSeen('1.0.0', 'banana')).toBeNull();
  });
  it('7: invalid lastSeen (1.2.3.4) -> null', () => {
    expect(detectUpgradeFromLastSeen('1.0.0', '1.2.3.4')).toBeNull();
  });
  it('8: major bump (2.0.0 > 1.9.0) -> lastSeen', () => {
    expect(detectUpgradeFromLastSeen('2.0.0', '1.9.0')).toBe('1.9.0');
  });
});
