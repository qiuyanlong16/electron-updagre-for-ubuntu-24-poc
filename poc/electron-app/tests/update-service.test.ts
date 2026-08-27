import { describe, it, expect } from 'vitest';
import { UpdateService } from '../src/main/update-service';

const okState = (v: string) => JSON.stringify({ status: 'installed', installedVersion: v, installedAt: '2026-08-27T10:00:00Z' });
const policy = (latestVersion: string, mode: 'optional' | 'force' = 'optional') =>
  Promise.resolve({ product: 'byclaw', channel: 'stable', latestVersion, minimumSupportedVersion: '1.0.0', mode, releaseNotes: [] });

describe('UpdateService', () => {
  it('corrupt state file -> fallback + stateSource=fallback + no throw', async () => {
    const svc = new UpdateService({ readStateFile: async () => '{ not json', runningVersion: '1.0.0', fetchPolicy: () => policy('1.0.0') });
    const s = await svc.compute();
    expect(s.stateSource).toBe('fallback');
    expect(s.installedVersion).toBe('1.0.0');
  });
  it('missing state file (ENOENT) -> fallback', async () => {
    const svc = new UpdateService({ readStateFile: async () => { const e = new Error('ENOENT'); throw e; }, runningVersion: '1.0.0', fetchPolicy: () => policy('1.0.0') });
    const s = await svc.compute();
    expect(s.stateSource).toBe('fallback');
    expect(s.installedVersion).toBe('1.0.0');
  });
  it('valid JSON but invalid-semver installedVersion -> fallback, no throw', async () => {
    const svc = new UpdateService({ readStateFile: async () => JSON.stringify({ installedVersion: 'abc' }), runningVersion: '1.0.0', fetchPolicy: () => policy('1.0.0') });
    const s = await svc.compute();
    expect(s.stateSource).toBe('fallback');
    expect(s.installedVersion).toBe('1.0.0');
    expect(s.state).toBe('LATEST');
  });
  it('valid installed-ahead from state file + latest equal -> READY_OPTIONAL', async () => {
    const svc = new UpdateService({ readStateFile: async () => okState('1.1.0'), runningVersion: '1.0.0', fetchPolicy: () => policy('1.1.0', 'optional') });
    const s = await svc.compute();
    expect(s.state).toBe('READY_OPTIONAL');
    expect(s.stateSource).toBe('update-state.json');
  });
  it('policy timeout -> ERROR, not freeze', async () => {
    const svc = new UpdateService({ readStateFile: async () => okState('1.0.0'), runningVersion: '1.0.0', fetchPolicy: () => new Promise(() => {}), policyTimeoutMs: 10 });
    const s = await svc.compute();
    expect(s.state).toBe('ERROR');
    expect(s.state).not.toBe('READY_FORCE');
  });
  it('policy returns invalid latestVersion -> ERROR', async () => {
    const svc = new UpdateService({ readStateFile: async () => okState('1.0.0'), runningVersion: '1.0.0', fetchPolicy: () => policy('not-a-version') });
    const s = await svc.compute();
    expect(s.state).toBe('ERROR');
    expect(s.error).toBe('invalid-latest-version');
  });
  it('repeated compute dedups concurrent fetchPolicy calls', async () => {
    let calls = 0;
    const svc = new UpdateService({
      readStateFile: async () => okState('1.0.0'),
      runningVersion: '1.0.0',
      fetchPolicy: async () => { calls++; await new Promise(r => setTimeout(r, 50)); return { product: 'byclaw', channel: 'stable', latestVersion: '1.0.0', minimumSupportedVersion: '1.0.0', mode: 'optional' as const, releaseNotes: [] }; },
    });
    const [a, b, c] = await Promise.all([svc.compute(), svc.compute(), svc.compute()]);
    expect(calls).toBe(1);
    expect(a).toEqual(b);
    expect(b).toEqual(c);
  });
  it('after a deduped batch, a later compute() runs a fresh fetch (inFlight reset)', async () => {
    let calls = 0;
    const svc = new UpdateService({
      readStateFile: async () => okState('1.0.0'),
      runningVersion: '1.0.0',
      fetchPolicy: async () => { calls++; return policy('1.0.0'); },
    });
    await Promise.all([svc.compute(), svc.compute(), svc.compute()]);
    expect(calls).toBe(1);
    await svc.compute();
    expect(calls).toBe(2); // proves finally cleared inFlight, not stuck
  });
  it('threads policy releaseNotes into the computed state', async () => {
    const svc = new UpdateService({
      readStateFile: async () => okState('1.0.0'),
      runningVersion: '1.0.0',
      fetchPolicy: async () => ({ latestVersion: '1.0.0', mode: 'optional', releaseNotes: ['fix x'] } as any),
    });
    const s = await svc.compute();
    expect(s.releaseNotes).toEqual(['fix x']);
  });
});
