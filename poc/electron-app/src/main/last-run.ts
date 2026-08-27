import { app } from 'electron';
import { writeFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { detectUpgradeFromLastSeen } from '../shared/upgrade-detect';

interface LastRun { lastSeenVersion?: string }

const filePath = () => join(app.getPath('userData'), 'last-run.json');

/** Read lastSeenVersion from the user-scoped userData dir (spec §11.1: never hardcode ~/.config). */
export function readLastSeen(): string | null {
  try {
    const p = filePath();
    if (!existsSync(p)) return null;
    const v = (JSON.parse(readFileSync(p, 'utf8')) as LastRun).lastSeenVersion;
    return typeof v === 'string' ? v : null; // guard: {"lastSeenVersion": 123} or null
  } catch { return null; }
}

/** Record currentVersion as seen, for next launch's detection (spec §11.2). */
export function markSeen(version: string): void {
  try {
    const dir = app.getPath('userData');
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'last-run.json'), JSON.stringify({ lastSeenVersion: version }));
  } catch (e) { console.error('[byclaw] last-run write failed:', e); }
}

/**
 * One-shot startup detection (spec §11.2): read lastSeen from disk, decide via the pure
 * detector, then unconditionally markSeen(currentVersion) so last-run.json is (re)created for
 * the NEXT launch. Returns the prior version (for the banner) or null.
 *
 * markSeen runs even when no upgrade is detected (first run / same / downgrade / corrupt) so a
 * missing or corrupt file is repaired on every launch. The returned value is held in memory for
 * the whole session (attached to every pushed state by main's decorate()) — the 5s poll never
 * re-reads disk mid-session, so the banner cannot flicker off once markSeen has advanced lastSeen.
 */
export function detectUpgrade(currentVersion: string): string | null {
  const lastSeen = readLastSeen();
  const result = detectUpgradeFromLastSeen(currentVersion, lastSeen);
  markSeen(currentVersion);
  return result;
}
