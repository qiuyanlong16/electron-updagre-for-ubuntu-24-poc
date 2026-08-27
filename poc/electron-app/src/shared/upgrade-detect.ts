import { gt, isValid } from './semver';

/**
 * Pure first-run-after-upgrade detection (spec §11.2).
 *
 * `currentVersion` is trusted (app.getVersion(), build-injected). `lastSeen` is UNTRUSTED —
 * read from disk; may be absent, non-string, or invalid semver.
 *
 * Returns the prior version string when an upgrade just happened (current > lastSeen),
 * else null. null for: no lastSeen (first run), invalid/corrupt lastSeen, same version, or
 * downgrade. Validation happens BEFORE gt() (which throws on invalid input) so a corrupt
 * last-run.json never crashes the main process at startup.
 */
export function detectUpgradeFromLastSeen(
  currentVersion: string,
  lastSeen: string | null,
): string | null {
  if (lastSeen === null) return null;
  if (!isValid(lastSeen) || !isValid(currentVersion)) return null;
  return gt(currentVersion, lastSeen) ? lastSeen : null;
}
