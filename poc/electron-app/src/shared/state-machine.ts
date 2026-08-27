import { gt } from './semver';
import type { UpdateState, UpdateStateName, UpdateMode } from '../renderer/types/update';

export interface StateInput {
  runningVersion: string;
  installedVersion: string;
  latestVersion: string | null;
  mode: UpdateMode | null;
  stateSource: 'update-state.json' | 'fallback';
  policyError: string | null;
  releaseNotes: string[];
}

/**
 * Pure update-state computation.
 *
 * Inputs runningVersion / installedVersion / latestVersion (when non-null) MUST be
 * valid semver strings; `gt()` throws on invalid semver (fail-fast). Callers
 * (update-service) are responsible for validating versions read from disk/network
 * before calling computeState, so garbage never reaches here.
 *
 * Rules (spec §7):
 *  - Only `installedVersion > runningVersion` sourced from the real state file
 *    (stateSource='update-state.json') yields READY_*; fallback never claims verified.
 *  - Force (READY_FORCE) only when installed-ahead AND mode==='force'.
 *  - latestVersion > running with installed not ahead -> UPDATE_AVAILABLE (discovered,
 *    not installed -> not frozen), regardless of mode.
 *  - policyError -> ERROR, never freeze.
 */
export function computeState(input: StateInput): UpdateState {
  const { runningVersion, installedVersion, latestVersion, mode, stateSource, policyError, releaseNotes } = input;
  const base: Omit<UpdateState, 'state'> = {
    runningVersion,
    installedVersion,
    latestVersion: latestVersion ?? runningVersion,
    mode,
    releaseNotes,
    stateSource,
  };

  if (policyError) {
    return { ...base, state: 'ERROR', error: policyError };
  }

  const installedAhead = stateSource === 'update-state.json' && gt(installedVersion, runningVersion);

  if (installedAhead) {
    if (mode === 'force') return { ...base, state: 'READY_FORCE' };
    return { ...base, state: 'READY_OPTIONAL' };
  }

  if (latestVersion && gt(latestVersion, runningVersion)) {
    return { ...base, state: 'UPDATE_AVAILABLE' };
  }
  return { ...base, state: 'LATEST' };
}

export const isFrozen = (s: UpdateStateName): boolean => s === 'READY_FORCE';
