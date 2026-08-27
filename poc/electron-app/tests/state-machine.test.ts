import { describe, it, expect } from 'vitest';
import { computeState, isFrozen, type StateInput } from '../src/shared/state-machine';

const base: StateInput = {
  runningVersion: '1.0.0',
  installedVersion: '1.0.0',
  latestVersion: '1.0.0',
  mode: 'optional',
  stateSource: 'update-state.json',
  policyError: null,
  releaseNotes: [],
};

describe('computeState', () => {
  it('1: 1.0.0 vs 1.0.0 -> LATEST', () => {
    expect(computeState({ ...base }).state).toBe('LATEST');
  });
  it('2: running 1.0.0 latest 1.1.0 installed 1.0.0 -> UPDATE_AVAILABLE', () => {
    expect(computeState({ ...base, latestVersion: '1.1.0' }).state).toBe('UPDATE_AVAILABLE');
  });
  it('3: running 1.0.0 installed 1.1.0 optional -> READY_OPTIONAL', () => {
    expect(computeState({ ...base, installedVersion: '1.1.0', latestVersion: '1.1.0', mode: 'optional' }).state).toBe('READY_OPTIONAL');
  });
  it('4: running 1.0.0 installed 1.1.0 force -> READY_FORCE', () => {
    expect(computeState({ ...base, installedVersion: '1.1.0', latestVersion: '1.1.0', mode: 'force' }).state).toBe('READY_FORCE');
  });
  it('5: 1.10.0 vs 1.9.0 correct (installed 1.10.0 running 1.9.0 -> READY_OPTIONAL)', () => {
    expect(computeState({ ...base, runningVersion: '1.9.0', installedVersion: '1.10.0', latestVersion: '1.10.0' }).state).toBe('READY_OPTIONAL');
  });
  it('6: stateSource=fallback -> UPDATE_AVAILABLE (never READY_* claiming verified)', () => {
    const s = computeState({ ...base, installedVersion: '1.1.0', latestVersion: '1.1.0', stateSource: 'fallback' });
    expect(s.state).toBe('UPDATE_AVAILABLE');
    expect(s.state).not.toBe('READY_OPTIONAL');
    expect(s.state).not.toBe('READY_FORCE');
    expect(s.stateSource).toBe('fallback');
  });
  it('7: policyError -> ERROR, no freeze', () => {
    expect(computeState({ ...base, policyError: 'timeout' }).state).toBe('ERROR');
  });
  it('8: no policy info (latest=null), no error -> LATEST', () => {
    expect(computeState({ ...base, latestVersion: null }).state).toBe('LATEST');
  });
  it('9: latest > running but installed <= running -> UPDATE_AVAILABLE even if mode=force (not freeze)', () => {
    const s = computeState({ ...base, latestVersion: '1.1.0', mode: 'force' });
    expect(s.state).toBe('UPDATE_AVAILABLE');
  });
  it('10: policyError + installed-ahead -> ERROR (precedence wins, no freeze)', () => {
    const s = computeState({ ...base, installedVersion: '1.1.0', latestVersion: '1.1.0', mode: 'force', policyError: 'timeout' });
    expect(s.state).toBe('ERROR');
    expect(s.error).toBe('timeout');
  });
});

describe('isFrozen', () => {
  it('READY_FORCE is frozen', () => {
    expect(isFrozen('READY_FORCE')).toBe(true);
  });
  it('other states are not frozen', () => {
    expect(isFrozen('READY_OPTIONAL')).toBe(false);
    expect(isFrozen('UPDATE_AVAILABLE')).toBe(false);
    expect(isFrozen('LATEST')).toBe(false);
    expect(isFrozen('CHECKING')).toBe(false);
    expect(isFrozen('RESTARTING')).toBe(false);
    expect(isFrozen('ERROR')).toBe(false);
  });
});
