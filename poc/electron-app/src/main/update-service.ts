import { computeState, type StateInput } from '../shared/state-machine';
import { isValid } from '../shared/semver';
import type { UpdatePolicy, UpdateState, UpdateMode } from '../shared/types/update';

export interface UpdateServiceDeps {
  readStateFile: () => Promise<string>;
  runningVersion: string;
  fetchPolicy: () => Promise<UpdatePolicy>;
  policyTimeoutMs?: number;
}

interface ParsedState { installedVersion?: unknown }

export class UpdateService {
  private inFlight: Promise<UpdateState> | null = null;
  constructor(private deps: UpdateServiceDeps) {}

  /**
   * Compute the current UpdateState. Concurrent calls are deduped (spec §18.1 case 9).
   *
   * `runningVersion` is trusted (from app.getVersion()) and is NOT re-validated here;
   * untrusted disk/network versions are validated with isValid before reaching the
   * throwing computeState (gt).
   */
  async compute(): Promise<UpdateState> {
    // Followers adopt the in-flight promise; only the leader (below) resets inFlight in finally.
    // Because compute() is async, a follower's `return this.inFlight` resolves to the leader's
    // value — behavioral dedup (same resolved value), not promise identity.
    if (this.inFlight) return this.inFlight;
    this.inFlight = (async () => {
      const { runningVersion, readStateFile, fetchPolicy, policyTimeoutMs = 3000 } = this.deps;

      // --- installedVersion from /var/lib/lenovo/byclaw/update-state.json ---
      // Validate semver BEFORE handing to computeState (gt throws on invalid).
      let installedVersion = runningVersion;
      let stateSource: StateInput['stateSource'] = 'fallback';
      try {
        const text = await readStateFile();
        const parsed: ParsedState = JSON.parse(text);
        const iv = parsed?.installedVersion;
        if (typeof iv === 'string' && isValid(iv)) {
          installedVersion = iv;
          stateSource = 'update-state.json';
        }
        // missing/invalid installedVersion -> keep fallback (no throw)
      } catch (e) {
        // missing/corrupt/unreadable state file: log, fallback, do NOT exit (spec §7.1, §7.4)
        console.error('[byclaw] update-state read failed, using fallback:', e);
      }

      // --- policy over local HTTP (fetch + timeout) ---
      let latestVersion: string | null = null;
      let mode: UpdateMode | null = null;
      let releaseNotes: string[] = [];
      let policyError: string | null = null;
      try {
        const p = await withTimeout(fetchPolicy(), policyTimeoutMs);
        if (typeof p.latestVersion !== 'string' || !isValid(p.latestVersion)) {
          policyError = 'invalid-latest-version';
        } else {
          latestVersion = p.latestVersion;
          const m = p.mode;
          // Untrusted network mode: only accept the two known values; anything else degrades
          // to null (→ optional path in computeState), matching the validation discipline applied
          // to installedVersion/latestVersion. Behavior-preserving for valid policies.
          mode = (m === 'optional' || m === 'force') ? m : null;
          releaseNotes = Array.isArray(p.releaseNotes) ? p.releaseNotes : [];
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : 'policy-fetch-failed';
        policyError = msg;
      }

      return computeState({ runningVersion, installedVersion, latestVersion, mode, stateSource, policyError, releaseNotes });
    })();
    try {
      return await this.inFlight;
    } finally {
      this.inFlight = null;
    }
  }
}

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    p.then(
      (v) => { clearTimeout(t); resolve(v); },
      (e) => { clearTimeout(t); reject(e); },
    );
  });
}
