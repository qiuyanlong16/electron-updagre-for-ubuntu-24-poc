# Byclaw Vue 3 + Electron Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the existing `nanobot` Electron POC (in `poc/`) into the `Byclaw` product — a Vue 3 + TypeScript + Vite + Electron app with a full update-awareness model (check / optional / force / restart), self-contained DEB via `electron-builder --dir` → `dpkg-deb`, a fixed aptly repo, minimal userns AppArmor, and 18 real-evidence validation cases.

**Architecture:** Renderer = Vue 3 SPA built by Vite; Electron main process owns the update state machine (semver comparison of running/installed/latest versions), polls `/var/lib/lenovo/byclaw/update-state.json` every 5 s, fetches `update-policy.json` over local HTTP, and pushes state changes to the renderer over a single safe `contextBridge` API. Packaging is two-layer: `electron-builder --dir` (version injected via `extraMetadata`, never mutating source `package.json`) → `linux-unpacked` → `dpkg-deb --root-owner-group --build`. APT/unattended-upgrades (root, background) installs; Electron never calls apt/dpkg/sudo/pkexec.

**Tech Stack:** Node 22, npm (existing lockfile), Vue 3, TypeScript, Vite, electron-builder, semver, Vitest, dpkg-deb, aptly, apparmor_parser, unattended-upgrade.

**Reference spec:** `docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md`

**Validation mode:** root steps are prepared as exact scripts, explained, and **paused for the user to run with `sudo`**; outputs are saved under `poc/evidence-v2/`; unexecuted root Cases are marked NOT TESTED, never PASS. No NOPASSWD, no sudo password handling.

---

## File Structure (decomposition)

**App source (rewrite `poc/electron-app/` in place):**
- `poc/electron-app/package.json` — deps + build scripts (version stays `0.0.0-dev`, never mutated by builds)
- `poc/electron-app/electron-builder.yml` — `--dir`/linux-unpacked target, extraMetadata version, asar
- `poc/electron-app/vite.config.ts` — renderer build (main/preload handled by electron-builder via tsup/esbuild)
- `poc/electron-app/tsconfig.json`, `vitest.config.ts`
- `poc/electron-app/src/shared/semver.ts` — pure semver compare (shared by main + tests)
- `poc/electron-app/src/shared/state-machine.ts` — pure state computation (input → UpdateState)
- `poc/electron-app/src/main/update-service.ts` — fs/net/io around the pure core; polling; IPC emit
- `poc/electron-app/src/main/ipc.ts` — `ipcMain.handle` registration
- `poc/electron-app/src/main/main.ts` — app lifecycle, BrowserWindow, sandbox, single-instance, restart
- `poc/electron-app/src/preload/preload.ts` — `contextBridge` 5-method API + unsubscribe
- `poc/electron-app/src/renderer/main.ts` — Vue mount
- `poc/electron-app/src/renderer/App.vue` — shell
- `poc/electron-app/src/renderer/composables/useUpdateState.ts` — subscribe/unsubscribe
- `poc/electron-app/src/renderer/components/VersionButton.vue`, `UpdateDialog.vue`
- `poc/electron-app/src/renderer/types/update.ts` — shared types
- `poc/electron-app/tests/semver.test.ts`, `state-machine.test.ts`, `update-service.test.ts`

**Packaging (new, self-contained):**
- `poc/packaging/byclaw/DEBIAN/control.tmpl`, `postinst.tmpl`, `prerm`, `postrm`
- `poc/packaging/byclaw/usr/share/applications/com.lenovo.byclaw.desktop`
- `poc/packaging/byclaw/etc/lenovo/byclaw/config.json`
- `poc/packaging/byclaw/etc/apparmor.d/com.lenovo.byclaw`
- `poc/packaging/byclaw/opt/lenovo/byclaw/resources/icon.png` (generated)
- `poc/scripts/build-version.sh`, `verify-versions.sh`

**Repo / policy / service:**
- `poc/apt-repository/aptly.conf`, `byclaw-poc-public.gpg`, `gpg-home/`, `aptly-db/`
- `poc/scripts/setup-repo.sh`, `publish-byclaw.sh`, `set-update-policy.sh`, `serve-repo.sh`, `install-client-config.sh`
- `poc/systemd/byclaw-poc-upgrade.service`, `.timer`
- `poc/client-config/byclaw-poc-repo-config/...`

**Tests + validation:**
- `poc/tests-v2/case-01.sh` … `case-18.sh`, `run-all-cases.sh`, `screenshot.sh`
- `poc/evidence-v2/` (outputs)
- `poc/VALIDATION_REPORT_V2.md`

**Docs:**
- `README.md`, `README.zh-CN.md` (update), `poc/README.md` (update), `docs/deployment/private-apt-contract.md`

Old `nanobot` files under `poc/electron-app/*.{js,html}`, `poc/scripts/build-deb.sh`, `poc/apparmor/com.lenovo.nanobot*`, `poc/systemd/nanobot-*`, `poc/tests/scenario-*.sh`, `poc/VALIDATION_REPORT.md` are **kept as-is** (history); new byclaw files live alongside.

---

## Phase 0 — Branch & scaffolding

### Task 0.1: Create the dev branch

**Files:** none (git only)

- [ ] **Step 1: Create and switch to feature branch**

Run:
```bash
cd /home/qiuyanlong/worespace/by-claw-poc-linux
git checkout -b feat/byclaw-vue3-redesign
```
Expected: `Switched to a new branch 'feat/byclaw-vue3-redesign'`

- [ ] **Step 2: Commit the design doc + plan**

```bash
git add docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md
git commit -m "docs: byclaw vue3 redesign design + implementation plan

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Phase 1 — Pure update-state machine (TDD, no Electron needed)

This phase is pure TypeScript testable with Vitest in isolation. It is the correctness-critical heart.

### Task 1.1: Vitest scaffolding + package.json

**Files:**
- Create: `poc/electron-app/package.json`
- Create: `poc/electron-app/vitest.config.ts`
- Create: `poc/electron-app/tsconfig.json`

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "byclaw",
  "version": "0.0.0-dev",
  "description": "Byclaw OEM assistant (Vue3 + Electron)",
  "author": "Lenovo",
  "license": "MIT",
  "main": "dist/main/main.js",
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit",
    "build:renderer": "vite build",
    "build:app": "electron-builder --dir",
    "build:version": "bash ../scripts/build-version.sh"
  },
  "devDependencies": {
    "electron": "^43.4.1",
    "electron-builder": "^25.1.8",
    "typescript": "^5.6.3",
    "vite": "^5.4.10",
    "vitest": "^2.1.4",
    "vue": "^3.5.13",
    "@vitejs/plugin-vue": "^5.2.1",
    "vite-plugin-electron": "^0.28.8",
    "vite-plugin-electron-renderer": "^0.14.6",
    "semver": "^7.6.3",
    "@types/node": "^22.9.0"
  },
  "dependencies": {
    "semver": "^7.6.3"
  }
}
```

> `electron` is a devDependency (build tooling). `version` is a dev baseline; builds inject the real version via `extraMetadata` and never write it back here.

- [ ] **Step 2: Write `vitest.config.ts`**

```ts
import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: { include: ['tests/**/*.test.ts'], environment: 'node' },
});
```

- [ ] **Step 3: Write `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "types": ["node", "vitest/globals"],
    "baseUrl": ".",
    "paths": { "@shared/*": ["src/shared/*"] }
  },
  "include": ["src", "tests"]
}
```

- [ ] **Step 4: Install deps**

Run: `cd poc/electron-app && npm install`
Expected: install completes; `package-lock.json` updated.

- [ ] **Step 5: Commit**

```bash
git add poc/electron-app/package.json poc/electron-app/package-lock.json poc/electron-app/vitest.config.ts poc/electron-app/tsconfig.json
git commit -m "feat(byclaw): scaffold electron-app package.json + vitest + tsconfig"
```

### Task 1.2: Shared types

**Files:** Create `poc/electron-app/src/renderer/types/update.ts`

- [ ] **Step 1: Write the types**

```ts
export type UpdateStateName =
  | 'CHECKING' | 'LATEST' | 'UPDATE_AVAILABLE'
  | 'READY_OPTIONAL' | 'READY_FORCE' | 'RESTARTING' | 'ERROR';

export type UpdateMode = 'optional' | 'force';

export interface UpdatePolicy {
  product: string;
  channel: string;
  latestVersion: string;
  minimumSupportedVersion: string;
  mode: UpdateMode;
  releaseNotes: string[];
}

export interface UpdateState {
  state: UpdateStateName;
  runningVersion: string;
  installedVersion: string;
  latestVersion: string;
  mode: UpdateMode | null;
  releaseNotes: string[];
  stateSource: 'update-state.json' | 'fallback';
  error?: string;
}
```

### Task 1.3: Pure semver compare (TDD)

**Files:**
- Create: `poc/electron-app/src/shared/semver.ts`
- Test: `poc/electron-app/tests/semver.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd poc/electron-app && npx vitest run tests/semver.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `src/shared/semver.ts`**

```ts
import { compare as semverCompare, valid } from 'semver';

export function compareSemver(a: string, b: string): -1 | 0 | 1 {
  if (!valid(a)) throw new Error(`invalid semver: ${a}`);
  if (!valid(b)) throw new Error(`invalid semver: ${b}`);
  return semverCompare(a, b) as -1 | 0 | 1;
}
export const gt = (a: string, b: string) => compareSemver(a, b) > 0;
export const lte = (a: string, b: string) => compareSemver(a, b) <= 0;
export const gte = (a: string, b: string) => compareSemver(a, b) >= 0;
```

> Using the `semver` package (allowed — it is the reference impl; not the banned `electron-updater`). Spec §7.3 requires semver not string compare.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd poc/electron-app && npx vitest run tests/semver.test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add poc/electron-app/src/shared/semver.ts poc/electron-app/tests/semver.test.ts
git commit -m "feat(byclaw): pure semver compare + tests"
```

### Task 1.4: Pure state machine (TDD) — covers spec §7 + §18.1 cases 1–4,6,7

**Files:**
- Create: `poc/electron-app/src/shared/state-machine.ts`
- Test: `poc/electron-app/tests/state-machine.test.ts`

- [ ] **Step 1: Write the failing test (spec §18.1 ten cases)**

```ts
import { describe, it, expect } from 'vitest';
import { computeState, type StateInput } from '../src/shared/state-machine';

const base: StateInput = {
  runningVersion: '1.0.0',
  installedVersion: '1.0.0',
  latestVersion: '1.0.0',
  mode: 'optional',
  stateSource: 'update-state.json',
  policyError: null,
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
  it('6: stateSource=fallback -> never READY_* claiming verified', () => {
    const s = computeState({ ...base, installedVersion: '1.1.0', latestVersion: '1.1.0', stateSource: 'fallback' });
    expect(s.state).not.toBe('READY_OPTIONAL');
    expect(s.state).not.toBe('READY_FORCE');
    expect(s.stateSource).toBe('fallback');
  });
  it('7: policyError -> ERROR, no freeze', () => {
    expect(computeState({ ...base, policyError: 'timeout' }).state).toBe('ERROR');
  });
  it('8: installed == running -> not READY_* (no waiting-for-restart)', () => {
    expect(computeState({ ...base, installedVersion: '1.0.0', latestVersion: '1.0.0' }).state).toBe('LATEST');
  });
  it('9: latest > running but installed <= running -> UPDATE_AVAILABLE even if mode=force (not freeze)', () => {
    const s = computeState({ ...base, latestVersion: '1.1.0', mode: 'force' });
    expect(s.state).toBe('UPDATE_AVAILABLE'); // not frozen: not yet installed
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd poc/electron-app && npx vitest run tests/state-machine.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `src/shared/state-machine.ts`**

```ts
import { gt, lte, gte } from './semver';
import type { UpdateState, UpdateStateName, UpdateMode } from '../renderer/types/update';

export interface StateInput {
  runningVersion: string;
  installedVersion: string;   // may equal runningVersion when fallback
  latestVersion: string | null; // null when policy unavailable
  mode: UpdateMode | null;
  stateSource: 'update-state.json' | 'fallback';
  policyError: string | null;
}

export function computeState(input: StateInput): UpdateState {
  const { runningVersion, installedVersion, latestVersion, mode, stateSource, policyError } = input;
  const releaseNotes: string[] = [];
  const base = { runningVersion, installedVersion, latestVersion: latestVersion ?? runningVersion, mode, releaseNotes, stateSource };

  // Policy fetch failed -> ERROR, never freeze (spec §7.5)
  if (policyError) {
    return { ...base, state: 'ERROR', error: policyError, latestVersion: latestVersion ?? runningVersion };
  }

  // Only installedVersion (verified from state file) > runningVersion may yield READY_*.
  // Fallback stateSource must NOT claim "verified installed" (spec §7.1, §17.5 rule).
  const installedAhead = stateSource === 'update-state.json' && gt(installedVersion, runningVersion);

  if (installedAhead) {
    if (mode === 'force') return { ...base, state: 'READY_FORCE' };
    return { ...base, state: 'READY_OPTIONAL' }; // optional is default-ish
  }

  // No installed-ahead: compare latest vs running.
  if (latestVersion && gt(latestVersion, runningVersion)) {
    return { ...base, state: 'UPDATE_AVAILABLE' }; // discovered, not installed -> not frozen
  }
  return { ...base, state: 'LATEST' };
}

export const isFrozen = (s: UpdateStateName) => s === 'READY_FORCE';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd poc/electron-app && npx vitest run tests/state-machine.test.ts`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add poc/electron-app/src/shared/state-machine.ts poc/electron-app/tests/state-machine.test.ts poc/electron-app/src/renderer/types/update.ts
git commit -m "feat(byclaw): pure update state machine + tests (covers spec §7)"
```

### Task 1.5: update-service I/O + dedup tests (TDD) — spec §18.1 cases 8–10

**Files:**
- Create: `poc/electron-app/src/main/update-service.ts`
- Test: `poc/electron-app/tests/update-service.test.ts`

- [ ] **Step 1: Write the failing test (timeout + dedup)**

```ts
import { describe, it, expect, vi } from 'vitest';
import { UpdateService } from '../src/main/update-service';

const ok = (s: string) => JSON.stringify({ status: 'installed', installedVersion: s, installedAt: '2026-08-27T10:00:00Z' });

describe('UpdateService', () => {
  it('corrupt state file -> fallback + stateSource=fallback + no throw', async () => {
    const svc = new UpdateService({
      readStateFile: async () => '{ not json',
      runningVersion: '1.0.0',
      fetchPolicy: async () => ({ latestVersion: '1.0.0', mode: 'optional' } as any),
    });
    const s = await svc.compute();
    expect(s.stateSource).toBe('fallback');
    expect(s.installedVersion).toBe('1.0.0');
  });
  it('policy timeout -> ERROR, not freeze', async () => {
    const svc = new UpdateService({
      readStateFile: async () => ok('1.0.0'),
      runningVersion: '1.0.0',
      fetchPolicy: async () => { throw new Error('timeout'); },
      policyTimeoutMs: 10,
    });
    const s = await svc.compute();
    expect(s.state).toBe('ERROR');
    expect(s.state).not.toBe('READY_FORCE');
  });
  it('repeated checkForUpdates dedups concurrent calls', async () => {
    let calls = 0;
    const svc = new UpdateService({
      readStateFile: async () => ok('1.0.0'),
      runningVersion: '1.0.0',
      fetchPolicy: async () => { calls++; await new Promise(r => setTimeout(r, 50)); return { latestVersion: '1.0.0', mode: 'optional' } as any; },
    });
    await Promise.all([svc.compute(), svc.compute(), svc.compute()]);
    expect(calls).toBe(1);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd poc/electron-app && npx vitest run tests/update-service.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `src/main/update-service.ts`**

```ts
import { computeState, type StateInput } from '../shared/state-machine';
import type { UpdatePolicy, UpdateState, UpdateMode } from '../renderer/types/update';

export interface UpdateServiceDeps {
  readStateFile: () => Promise<string>;       // returns raw text; may throw
  runningVersion: string;
  fetchPolicy: () => Promise<UpdatePolicy>;    // may throw (timeout/network)
  policyTimeoutMs?: number;
}

interface ParsedState { installedVersion: string; }

export class UpdateService {
  private inFlight: Promise<UpdateState> | null = null;
  constructor(private deps: UpdateServiceDeps) {}

  async compute(): Promise<UpdateState> {
    if (this.inFlight) return this.inFlight; // dedup concurrent (spec §18.1 case 9)
    this.inFlight = (async () => {
      const { runningVersion, readStateFile, fetchPolicy, policyTimeoutMs = 3000 } = this.deps;
      // installedVersion
      let installedVersion = runningVersion;
      let stateSource: StateInput['stateSource'] = 'fallback';
      try {
        const text = await readStateFile();
        const parsed: ParsedState = JSON.parse(text);
        if (parsed && typeof parsed.installedVersion === 'string' && parsed.installedVersion) {
          installedVersion = parsed.installedVersion;
          stateSource = 'update-state.json';
        }
      } catch (e) {
        // missing/corrupt/unreadable: log, fallback, do NOT exit (spec §7.1, §7.4)
        console.error('[byclaw] update-state read failed, using fallback:', e);
      }
      // policy
      let latestVersion: string | null = null;
      let mode: UpdateMode | null = null;
      let releaseNotes: string[] = [];
      let policyError: string | null = null;
      try {
        const p = await withTimeout(fetchPolicy(), policyTimeoutMs);
        latestVersion = p.latestVersion;
        mode = p.mode;
        releaseNotes = p.releaseNotes ?? [];
      } catch (e: any) {
        policyError = e?.message ?? 'policy-fetch-failed';
      }
      return computeState({ runningVersion, installedVersion, latestVersion, mode, stateSource, policyError, releaseNotes } as any)
        && { ...computeState({ runningVersion, installedVersion, latestVersion, mode, stateSource, policyError }), releaseNotes };
    })();
    try { return await this.inFlight; } finally { this.inFlight = null; }
  }
}

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('timeout')), ms);
    p.then(v => { clearTimeout(t); resolve(v); }, e => { clearTimeout(t); reject(e); });
  });
}
```

> Note: the `&& {...}` line is a smell — simplify in Step 3b below.

- [ ] **Step 3b: Simplify return (carry releaseNotes through computeState)**

The pure `computeState` already accepts `releaseNotes` via `StateInput`? It doesn't yet. Update `state-machine.ts` `StateInput` to include `releaseNotes: string[]` and thread it into the returned `UpdateState`. Replace the `update-service.ts` compute return with:

```ts
return computeState({ runningVersion, installedVersion, latestVersion, mode, stateSource, policyError, releaseNotes });
```

And in `state-machine.ts` add `releaseNotes: string[];` to `StateInput` and set `releaseNotes` in `base`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd poc/electron-app && npx vitest run tests/update-service.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add poc/electron-app/src/main/update-service.ts poc/electron-app/tests/update-service.test.ts poc/electron-app/src/shared/state-machine.ts
git commit -m "feat(byclaw): update-service (fs/net/io + dedup + timeout) + tests"
```

---

## Phase 2 — Electron main + preload + IPC

### Task 2.1: Preload safe API

**Files:** Create `poc/electron-app/src/preload/preload.ts`

- [ ] **Step 1: Write preload**

```ts
import { contextBridge, ipcRenderer } from 'electron';
import type { UpdateState } from '../renderer/types/update';

const CHANNEL = 'byclaw:update-state-changed';

contextBridge.exposeInMainWorld('byclawAPI', {
  getCurrentVersion: (): Promise<string> => ipcRenderer.invoke('byclaw:get-current-version'),
  checkForUpdates: (): Promise<UpdateState> => ipcRenderer.invoke('byclaw:check-for-updates'),
  getUpdateState: (): Promise<UpdateState> => ipcRenderer.invoke('byclaw:get-update-state'),
  restartApplication: (): Promise<void> => ipcRenderer.invoke('byclaw:restart-application'),
  onUpdateStateChanged: (cb: (s: UpdateState) => void): (() => void) => {
    const listener = (_e: unknown, state: UpdateState) => cb(state);
    ipcRenderer.on(CHANNEL, listener);
    return () => { ipcRenderer.removeListener(CHANNEL, listener); };
  },
});
```

> Only these 5 methods are exposed. No `ipcRenderer` object, no `fs`/`child_process`/`shell`, no arbitrary channel access. `onUpdateStateChanged` returns an unsubscribe (spec §6.2).

### Task 2.2: IPC registration

**Files:** Create `poc/electron-app/src/main/ipc.ts`

- [ ] **Step 1: Write ipc.ts**

```ts
import { ipcMain, app, BrowserWindow } from 'electron';
import { UpdateService } from './update-service';
import { UpdatePolicy } from '../renderer/types/update';
import { readFileSync } from 'node:fs';

const STATE_PATH = '/var/lib/lenovo/byclaw/update-state.json';
const CONFIG_PATH = '/etc/lenovo/byclaw/config.json';

function readStateFile(): Promise<string> {
  return Promise.resolve().then(() => readFileSync(STATE_PATH, 'utf8'));
}

function readPolicyUrl(): string {
  try {
    const cfg = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
    return cfg.updatePolicyUrl as string;
  } catch {
    return 'http://127.0.0.1:8099/update-policy.json';
  }
}

export function createService(runningVersion: string): UpdateService {
  return new UpdateService({
    runningVersion,
    readStateFile,
    fetchPolicy: async (): Promise<UpdatePolicy> => {
      const url = readPolicyUrl();
      const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
      if (!res.ok) throw new Error(`policy http ${res.status}`);
      return (await res.json()) as UpdatePolicy;
    },
  });
}

export function registerIpc(service: UpdateService, getWindow: () => BrowserWindow | null) {
  ipcMain.handle('byclaw:get-current-version', () => app.getVersion());
  ipcMain.handle('byclaw:check-for-updates', () => service.compute());
  ipcMain.handle('byclaw:get-update-state', () => service.compute());
  ipcMain.handle('byclaw:restart-application', () => {
    app.relaunch();
    app.exit(0);
  });
}

export function pushState(getWindow: () => BrowserWindow | null, state: any) {
  getWindow()?.webContents.send('byclaw:update-state-changed', state);
}
```

> The running Electron app reads only the two root-owned files (`/etc/.../config.json`, `/var/lib/.../update-state.json`) and the local HTTP policy. It does NOT call apt/dpkg/sudo/pkexec. `fetch` is available in Node 22 main process.

### Task 2.3: main.ts — lifecycle, sandbox, single instance, polling

**Files:** Create `poc/electron-app/src/main/main.ts`

- [ ] **Step 1: Write main.ts**

```ts
import { app, BrowserWindow } from 'electron';
import * as path from 'node:path';
import { createService, registerIpc, pushState } from './ipc';

// Refuse --no-sandbox (spec §6.1, §13.2)
if (app.commandLine.hasSwitch('no-sandbox')) {
  console.error('ERROR: --no-sandbox is not allowed.');
  app.exit(1);
}
app.enableSandbox();

// Single instance (spec §10)
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) { app.exit(0); }

let mainWindow: BrowserWindow | null = null;
const service = createService(app.getVersion());

app.whenReady().then(async () => {
  registerIpc(service, () => mainWindow);

  mainWindow = new BrowserWindow({
    width: 960, height: 680,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  mainWindow.loadFile(path.join(__dirname, 'renderer/index.html'));

  // Initial state + 5s poll (spec §7.4)
  const tick = async () => { const s = await service.compute(); pushState(() => mainWindow, s); };
  await tick();
  setInterval(tick, 5000);
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
```

- [ ] **Step 2: Commit Phase 2**

```bash
git add poc/electron-app/src/preload poc/electron-app/src/main
git commit -m "feat(byclaw): electron main + preload safe API + ipc"
```

---

## Phase 3 — Vue 3 renderer

### Task 3.1: Vite config + entry

**Files:**
- Create: `poc/electron-app/vite.config.ts`
- Create: `poc/electron-app/src/renderer/main.ts`
- Create: `poc/electron-app/src/renderer/index.html` (at repo root for vite, copied by build)

- [ ] **Step 1: `vite.config.ts`**

```ts
import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import electron from 'vite-plugin-electron';
import renderer from 'vite-plugin-electron-renderer';

export default defineConfig({
  plugins: [
    vue(),
    electron([
      { entry: 'src/main/main.ts', vite: { build: { outDir: 'dist/main', rollupOptions: { output: { entryFileNames: 'main.js' } } } } },
      { entry: 'src/preload/preload.ts', vite: { build: { outDir: 'dist/preload', rollupOptions: { output: { entryFileNames: 'preload.js' } } } } },
    ]),
    renderer(),
  ],
  build: { outDir: 'dist/renderer' },
});
```

> Preload stays CJS-compatible (sandbox). `vite-plugin-electron` builds main/preload to CJS by default.

- [ ] **Step 2: `src/renderer/index.html`**

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="UTF-8" /><title>Byclaw</title></head>
<body><div id="app"></div><script type="module" src="./main.ts"></script></body>
</html>
```

- [ ] **Step 3: `src/renderer/main.ts`**

```ts
import { createApp } from 'vue';
import App from './App.vue';
createApp(App).mount('#app');
```

### Task 3.2: useUpdateState composable

**Files:** Create `poc/electron-app/src/renderer/composables/useUpdateState.ts`

- [ ] **Step 1: Write composable (unsubscribe on unmount)**

```ts
import { ref, onMounted, onUnmounted } from 'vue';
import type { UpdateState } from '../types/update';

declare global { interface Window { byclawAPI: any } }

export function useUpdateState() {
  const state = ref<UpdateState | null>(null);
  const checking = ref(false);
  let unsub: (() => void) | null = null;

  onMounted(async () => {
    const api = window.byclawAPI;
    state.value = await api.getUpdateState();
    unsub = api.onUpdateStateChanged((s: UpdateState) => { state.value = s; });
  });
  onUnmounted(() => { unsub?.(); });

  async function check() {
    if (checking.value) return; // dedup (spec §18.1 case 9)
    checking.value = true;
    try { state.value = await window.byclawAPI.checkForUpdates(); }
    finally { checking.value = false; }
  }

  async function restart() {
    state.value = { ...(state.value as any), state: 'RESTARTING' } as UpdateState;
    await window.byclawAPI.restartApplication(); // dedup handled by UI disable (spec §18.1 case 10)
  }

  return { state, checking, check, restart };
}
```

### Task 3.3: VersionButton + App.vue + UpdateDialog

**Files:**
- Create `poc/electron-app/src/renderer/components/VersionButton.vue`
- Create `poc/electron-app/src/renderer/components/UpdateDialog.vue`
- Create `poc/electron-app/src/renderer/App.vue`

- [ ] **Step 1: `VersionButton.vue`**

```vue
<template>
  <button class="version-btn" :disabled="checking" @click="check">
    <span class="ver">版本 v{{ currentVersion }}</span>
    <span class="hint">{{ hint }}</span>
  </button>
</template>
<script setup lang="ts">
import { computed } from 'vue';
const props = defineProps<{ currentVersion: string; checking: boolean; stateName: string }>();
const emit = defineEmits<{ check: [] }>();
const check = () => emit('check');
const hint = computed(() => {
  if (props.checking) return '正在检查更新';
  if (props.stateName === 'LATEST') return '当前已是最新版本';
  return '点击检查更新';
});
</script>
```

- [ ] **Step 2: `UpdateDialog.vue` (3 dialogs, force rules spec §5.3)**

```vue
<template>
  <div v-if="visible" class="overlay" :class="{ frozen: force }">
    <div class="dialog">
      <template v-if="state === 'UPDATE_AVAILABLE'">
        <h2>发现新版本 {{ latestVersion }}</h2>
        <p>Ubuntu 正在后台准备更新，整个过程不需要输入密码。<br />更新完成后，Byclaw 会通知你重启应用。</p>
        <div class="actions"><button @click="$emit('close')">知道了</button></div>
      </template>
      <template v-else-if="state === 'READY_OPTIONAL'">
        <h2>Byclaw {{ installedVersion }} 已经安装完成</h2>
        <p>重启应用后即可使用新版本。</p>
        <div class="actions"><button @click="$emit('close')">稍后重启</button><button class="primary" @click="$emit('restart')">立即重启</button></div>
      </template>
      <template v-else-if="state === 'READY_FORCE'">
        <h2>必须更新 Byclaw</h2>
        <p>新版本已经安装完成，需要重启后继续使用。</p>
        <div class="actions"><button class="primary" @click="$emit('restart')">立即重启</button></div>
      </template>
      <template v-else-if="state === 'RESTARTING'">
        <h2>正在重启…</h2>
      </template>
    </div>
  </div>
</template>
<script setup lang="ts">
defineProps<{ visible: boolean; state: string; force: boolean; latestVersion: string; installedVersion: string }>();
defineEmits<{ close: []; restart: [] }>();
</script>
<style scoped>
.overlay { position: fixed; inset: 0; background: rgba(0,0,0,.5); display: flex; align-items: center; justify-content: center; z-index: 9999; }
.dialog { background: #16213e; color: #e8e8f0; border-radius: 12px; padding: 32px; max-width: 440px; }
.actions { display: flex; gap: 12px; justify-content: flex-end; margin-top: 20px; }
button.primary { background: #00d4ff; color: #001020; font-weight: 700; }
.frozen { } /* force: no close on overlay/Esc (handled by no close button) */
</style>
```

> Force: no close button, no overlay-click close, no Esc (no `@click` on overlay, no keydown handler). Frozen main area is controlled in App.vue.

- [ ] **Step 3: `App.vue`**

```vue
<template>
  <div class="app" :class="{ frozen: force }">
    <header><h1>Byclaw</h1></header>
    <main>
      <VersionButton :current-version="runningVersion" :checking="checking" :state-name="stateName" @check="check" />
      <p v-if="upgradedBanner" class="banner">Byclaw 已更新到 {{ runningVersion }}</p>
    </main>
    <UpdateDialog
      :visible="dialogVisible"
      :state="stateName"
      :force="force"
      :latest-version="latestVersion"
      :installed-version="installedVersion"
      @close="onClose"
      @restart="restart" />
  </div>
</template>
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import VersionButton from './components/VersionButton.vue';
import UpdateDialog from './components/UpdateDialog.vue';
import { useUpdateState } from './composables/useUpdateState';

const { state, checking, check, restart } = useUpdateState();
const runningVersion = computed(() => state.value?.runningVersion ?? '');
const stateName = computed(() => state.value?.state ?? 'CHECKING');
const latestVersion = computed(() => state.value?.latestVersion ?? '');
const installedVersion = computed(() => state.value?.installedVersion ?? '');
const force = computed(() => stateName.value === 'READY_FORCE');
const dialogVisible = computed(() => ['UPDATE_AVAILABLE', 'READY_OPTIONAL', 'READY_FORCE', 'RESTARTING'].includes(stateName.value));
const upgradedBanner = ref(false);

function onClose() { /* only optional/UPDATE_AVAILABLE dismiss; force has no close button */ }

onMounted(async () => {
  // first-run-after-upgrade banner (spec §11)
  const api = window.byclawAPI;
  const ver = await api.getCurrentVersion();
  const path = await import('electron').then(() => ''); // userData not available in renderer; use lastSeen via main? -> see note
  // We store lastSeenVersion via a dedicated IPC not in scope of preload surface;
  // per spec §11 we use app.getPath('userData') in MAIN and expose lastSeen via getUpdateState.
  upgradedBanner.value = false; // placeholder until main exposes lastSeen
});
</script>
<style scoped>
.app { min-height: 100vh; background: linear-gradient(135deg, #1a1a2e, #16213e); color: #e8e8f0; }
.frozen main { pointer-events: none; opacity: .45; filter: grayscale(.4); }
.banner { color: #00d4ff; }
</style>
```

> **Note on §11 lastSeenVersion:** `app.getPath('userData')` is only available in the main process. To keep the preload surface at exactly 5 methods (spec §6.2), the first-run banner is computed in main and surfaced via `getUpdateState()` — i.e. `UpdateState` gains an optional `upgradedFrom?: string` field set by main when `getVersion() > lastSeenVersion`. Task 3.4 wires this.

- [ ] **Step 4: Commit**

```bash
git add poc/electron-app/src/renderer poc/electron-app/vite.config.ts
git commit -m "feat(byclaw): vue3 renderer (App, VersionButton, UpdateDialog, composable)"
```

### Task 3.4: First-run-after-upgrade in main (spec §11)

**Files:** Modify `poc/electron-app/src/main/ipc.ts` + `update-service.ts`; add `src/main/last-run.ts`

- [ ] **Step 1: Add `src/main/last-run.ts`**

```ts
import { app } from 'electron';
import { writeFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { gte } from '../shared/semver';

interface LastRun { lastSeenVersion?: string }

export function readLastSeen(): string | null {
  try {
    const p = join(app.getPath('userData'), 'last-run.json');
    if (!existsSync(p)) return null;
    return (JSON.parse(readFileSync(p, 'utf8')) as LastRun).lastSeenVersion ?? null;
  } catch { return null; }
}

export function markSeen(version: string) {
  try {
    const dir = app.getPath('userData');      // user-scoped, not hardcoded ~/.config (spec §11.1)
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'last-run.json'), JSON.stringify({ lastSeenVersion: version }));
  } catch (e) { console.error('[byclaw] last-run write failed:', e); }
}

// returns prior version if an upgrade just happened (new > lastSeen), else null; only when lastSeen exists
export function detectUpgrade(currentVersion: string): string | null {
  const lastSeen = readLastSeen();
  if (!lastSeen) { markSeen(currentVersion); return null; } // first run, no banner (spec §11.2)
  if (gte(currentVersion, lastSeen) && currentVersion !== lastSeen) {
    return lastSeen; // banner "已更新到 currentVersion"
  }
  return null;
}
```

- [ ] **Step 2: Wire into `ipc.ts`** — add `upgradedFrom` to the computed state at startup and call `markSeen(getVersion())` after first compute.

In `ipc.ts` `createService`, after constructing, the main entry (main.ts) will call `detectUpgrade(app.getVersion())` once at startup and attach `upgradedFrom` to the first pushed state. Add to `UpdateState` type an optional `upgradedFrom?: string`.

- [ ] **Step 3: Update `App.vue` banner** to read `state.value?.upgradedFrom`.

- [ ] **Step 4: Commit**

```bash
git add poc/electron-app/src/main/last-run.ts poc/electron-app/src/main/ipc.ts poc/electron-app/src/renderer
git commit -m "feat(byclaw): first-run-after-upgrade banner via app.getPath('userData')"
```

---

## Phase 4 — Two-layer packaging

### Task 4.1: electron-builder.yml (--dir, no deb)

**Files:** Create `poc/electron-app/electron-builder.yml`

- [ ] **Step 1: Write config**

```yaml
appId: com.lenovo.byclaw
productName: byclaw
directories:
  output: ../dist-electron
files:
  - dist/main/**
  - dist/preload/**
  - dist/renderer/**
asar: true
linux:
  target:
    - dir
  category: Utility
  executableName: byclaw
  maintainer: Lenovo OEM <oem@lenovo.com>
```

> `target: dir` → `linux-unpacked`, NO deb (spec §四). Version injected via `extraMetadata.version` on the CLI in build-version.sh.

### Task 4.2: Packaging tree templates

**Files:**
- Create: `poc/packaging/byclaw/DEBIAN/control.tmpl`
- Create: `poc/packaging/byclaw/DEBIAN/postinst.tmpl`
- Create: `poc/packaging/byclaw/DEBIAN/prerm`
- Create: `poc/packaging/byclaw/DEBIAN/postrm`
- Create: `poc/packaging/byclaw/usr/share/applications/com.lenovo.byclaw.desktop`
- Create: `poc/packaging/byclaw/etc/lenovo/byclaw/config.json`
- Create: `poc/packaging/byclaw/etc/apparmor.d/com.lenovo.byclaw`

- [ ] **Step 1: `control.tmpl`**

```
Package: byclaw
Version: __VERSION__
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Lenovo OEM <oem@lenovo.com>
Installed-Size: __INSTALLED_SIZE__
Description: Byclaw OEM Assistant
 Vue3 + Electron OEM assistant. Installed to /opt/lenovo/byclaw.
 Auto-upgrade via APT + unattended-upgrades. Electron never calls apt/dpkg/sudo.
```

- [ ] **Step 2: `postinst.tmpl` (atomic write, build-time `__VERSION__` injection; spec §9)**

```bash
#!/bin/bash
set -e
VERSION="__VERSION__"
STATE_DIR="/var/lib/lenovo/byclaw"
STATE_FILE="${STATE_DIR}/update-state.json"
MODELS_DIR="${STATE_DIR}/models"

mkdir -p "${STATE_DIR}" "${MODELS_DIR}"
chmod 0755 "${STATE_DIR}" "${MODELS_DIR}"
chown root:root "${STATE_DIR}" "${MODELS_DIR}"

# Atomic write of update-state.json (temp + mv), idempotent (spec §9.1)
TMP="$(mktemp "${STATE_FILE}.XXXXXX")"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "${TMP}" <<EOF
{
  "status": "installed",
  "installedVersion": "${VERSION}",
  "installedAt": "${NOW}"
}
EOF
chown root:root "${TMP}"
chmod 0644 "${TMP}"
mv -f "${TMP}" "${STATE_FILE}"

# Refresh desktop database
update-desktop-database /usr/share/applications 2>/dev/null || logger -t byclaw "postinst: desktop-db refresh soft-failed"

# Load AppArmor profile (do not fail install; Case 7 records real enforce) (spec §13.8)
if command -v apparmor_parser >/dev/null 2>&1 && [ -f /etc/apparmor.d/com.lenovo.byclaw ]; then
  apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw 2>/dev/null || logger -t byclaw "postinst: apparmor reload soft-failed"
fi

logger -t byclaw "Byclaw ${VERSION} installed successfully"
exit 0
```

> `__VERSION__` is substituted at build time by `build-version.sh` (sed), so no runtime `${VERSION}` undefined-var bug (fixes D1). `installedVersion` is the literal baked version; `installedAt` is runtime `date`.

- [ ] **Step 3: `prerm`**

```bash
#!/bin/bash
set -e
update-desktop-database /usr/share/applications 2>/dev/null || true
logger -t byclaw "Byclaw prerm executed"
exit 0
```

- [ ] **Step 4: `postrm` (purge cleans system-side only; never user Home; spec §9.2)**

```bash
#!/bin/bash
set -e
if [ "$1" = "purge" ]; then
  rm -rf /var/lib/lenovo/byclaw /etc/lenovo/byclaw
  logger -t byclaw "Byclaw purged (system-side data removed; user data preserved)"
fi
exit 0
```

- [ ] **Step 5: `com.lenovo.byclaw.desktop`**

```ini
[Desktop Entry]
Type=Application
Name=Byclaw
GenericName=Lenovo OEM Assistant
Exec=/opt/lenovo/byclaw/byclaw %U
Icon=/opt/lenovo/byclaw/resources/icon.png
Terminal=false
Categories=Utility;
Keywords=lenovo;oem;byclaw;
StartupWMClass=byclaw
```

- [ ] **Step 6: `config.json` (root-owned policy URL; spec §8.3)**

```json
{
  "updatePolicyUrl": "http://127.0.0.1:8099/update-policy.json"
}
```

- [ ] **Step 7: AppArmor profile `com.lenovo.byclaw` (spec §13)**

```
abi <abi/4.0>,
include <tunables/global>

/opt/lenovo/byclaw/byclaw flags=(unconfined) {
  userns,
  include if exists <local/com.lenovo.byclaw>
}
```

> Subject path must match the real electron-builder entry binary; confirmed empirically in Case 7 (§13.3). No sys_admin/sys_chroot/dac_read_search/setuid/setgid/fowner/chown, no /etc/** /proc/** rw /sys/**, no chrome-sandbox 4755.

### Task 4.3: build-version.sh + verify-versions.sh

**Files:**
- Create: `poc/scripts/build-version.sh`
- Create: `poc/scripts/verify-versions.sh`

- [ ] **Step 1: `build-version.sh` (single version source; spec §12)**

```bash
#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?usage: build-version.sh <version> e.g. 1.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/electron-app"
PKG_DIR="$ROOT/packages"
STAGE="$PKG_DIR/build-${VERSION}"
DEB="$PKG_DIR/byclaw_${VERSION}_amd64.deb"

echo "[build] version=${VERSION}"
cd "$APP"
npm install --no-audit --no-fund
npx vitest run                    # unit tests must pass before packaging
npx vite build                    # renderer -> dist/renderer; main/preload -> dist/main, dist/preload
# electron-builder --dir with extraMetadata.version (does NOT mutate source package.json) (spec §12.2)
npx electron-builder --dir --config.extraMetadata.version="${VERSION}"
# electron-builder output: $ROOT/dist-electron/linux-unpacked

UNPACKED="$ROOT/dist-electron/linux-unpacked"
[ -d "$UNPACKED" ] || { echo "ERROR: linux-unpacked missing"; exit 1; }

echo "[build] stage DEB tree"
rm -rf "$STAGE"
mkdir -p "$STAGE/opt/lenovo/byclaw"
cp -a "$UNPACKED/." "$STAGE/opt/lenovo/byclaw/"

# packaging overlays
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/share/applications" "$STAGE/etc/lenovo/byclaw" "$STAGE/etc/apparmor.d" "$STAGE/opt/lenovo/byclaw/resources"
cp "$ROOT/packaging/byclaw/usr/share/applications/com.lenovo.byclaw.desktop" "$STAGE/usr/share/applications/"
cp "$ROOT/packaging/byclaw/etc/lenovo/byclaw/config.json" "$STAGE/etc/lenovo/byclaw/"
cp "$ROOT/packaging/byclaw/etc/apparmor.d/com.lenovo.byclaw" "$STAGE/etc/apparmor.d/"
# icon (generated placeholder if absent)
if [ ! -f "$STAGE/opt/lenovo/byclaw/resources/icon.png" ]; then
  "$ROOT/scripts/make-icon.sh" "$STAGE/opt/lenovo/byclaw/resources/icon.png" || true
fi

# maintainer scripts with version injection
sed "s/__VERSION__/${VERSION}/g" "$ROOT/packaging/byclaw/DEBIAN/control.tmpl" > "$STAGE/DEBIAN/control"
INSTALLED_SIZE="$(du -sk "$STAGE/opt/lenovo/byclaw" | cut -f1)"
sed -i "s/__INSTALLED_SIZE__/${INSTALLED_SIZE}/" "$STAGE/DEBIAN/control"
sed "s/__VERSION__/${VERSION}/g" "$ROOT/packaging/byclaw/DEBIAN/postinst.tmpl" > "$STAGE/DEBIAN/postinst"
cp "$ROOT/packaging/byclaw/DEBIAN/prerm" "$STAGE/DEBIAN/prerm"
cp "$ROOT/packaging/byclaw/DEBIAN/postrm" "$STAGE/DEBIAN/postrm"
chmod 0755 "$STAGE/DEBIAN/"{postinst,prerm,postrm}

# perms: dirs 0755, files 0644, entry 0755 (chrome-sandbox stays 0755 NOT 4755) (spec §13.4, §16)
find "$STAGE" -type d -exec chmod 0755 {} \;
find "$STAGE/opt/lenovo/byclaw" -type f -exec chmod 0644 {} \;
chmod 0755 "$STAGE/opt/lenovo/byclaw/byclaw" 2>/dev/null || true
# chrome-sandbox explicitly NOT setuid
[ -f "$STAGE/opt/lenovo/byclaw/chrome-sandbox" ] && chmod 0755 "$STAGE/opt/lenovo/byclaw/chrome-sandbox"

# build update-policy.json as a build artifact (latestVersion = VERSION) (spec §12.3 #5)
mkdir -p "$ROOT/apt-repository/aptly-db/public"
cat > "$ROOT/apt-repository/aptly-db/public/update-policy.json" <<EOF
{
  "product": "byclaw",
  "channel": "stable",
  "latestVersion": "${VERSION}",
  "minimumSupportedVersion": "1.0.0",
  "mode": "optional",
  "releaseNotes": ["Byclaw ${VERSION}"]
}
EOF

echo "[build] dpkg-deb"
dpkg-deb --root-owner-group --build "$STAGE" "$DEB"

echo "[build] verify six-place version consistency"
bash "$ROOT/scripts/verify-versions.sh" "$VERSION" "$DEB" "$ROOT/apt-repository/aptly-db/public/update-policy.json"

echo "[build] OK -> $DEB"
```

- [ ] **Step 2: `verify-versions.sh` (spec §12.3, six places)**

```bash
#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?version}"
DEB="${2:?deb}"
POLICY="${3:?update-policy.json}"
fail=0
chk() { # <label> <actual>
  if [ "$2" = "$1" ]; then echo "  OK   $3 = $2"; else echo "  FAIL $3 = $2 (expected $1)"; fail=1; fi
}
echo "[verify] expected version: $VERSION"

# 1. app.getVersion() <- deb's packaged package.json (inside app.asar not readable; use electron-builder metadata)
#    We approximate #1 by checking the deb contains the productName binary and control Version (#2).
#    Full #1 verification happens at runtime in Case 13 (app reports its version).

# 2. control Version
CTRL="$(dpkg-deb -f "$DEB" Version)"
chk "$VERSION" "$CTRL" "DEBIAN/control Version (#2)"

# 3. postinst installedVersion (baked literal)
POSTINST="$(dpkg-deb --fsys-tarfile "$DEB" | tar -xO ./DEBIAN/postinst 2>/dev/null | grep -o 'installedVersion": "[^"]*"' | head -1 | sed 's/.*": "//;s/"$//')"
chk "$VERSION" "$POSTINST" "postinst installedVersion (#3)"

# 4. deb filename
case "$(basename "$DEB")" in byclaw_${VERSION}_amd64.deb) echo "  OK   filename (#4)";; *) echo "  FAIL filename (#4)"; fail=1;; esac

# 5. update-policy latestVersion
LATEST="$(python3 -c "import json,sys;print(json.load(open('$POLICY'))['latestVersion'])")"
chk "$VERSION" "$LATEST" "update-policy latestVersion (#5)"

# 6. APT Packages index Version — only checkable after publish; here we skip with a note
echo "  NOTE Packages-index (#6) verified post-publish by verify-versions.sh --published"

[ $fail -eq 0 ] || { echo "[verify] FAILED"; exit 1; }
echo "[verify] build-time checks OK"
```

- [ ] **Step 3: `make-icon.sh` (placeholder icon generator)**

```bash
#!/usr/bin/env bash
# generate a 256x256 solid PNG icon if none exists (so desktop entry has an icon)
OUT="${1:?out path}"
python3 - "$OUT" <<'PY'
import sys,struct,zlib
out=sys.argv[1]
w=h=256
raw=bytearray()
for y in range(h):
  raw.append(0)  # filter none
  for x in range(w):
    raw += bytes([0x16,0x21,0x3e,0xff])  # #16213e
def chunk(t,d):
  c=t+d; return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
sig=b'\x89PNG\r\n\x1a\n'
ihdr=struct.pack('>IIBBBBB',w,h,8,6,0,0,0)
idat=zlib.compress(bytes(raw),9)
open(out,'wb').write(sig+chunk(b'IHDR',ihdr)+chunk(b'IDAT',idat)+chunk(b'IEND',b''))
PY
```

- [ ] **Step 4: Build 1.0.0 (normal user)**

Run:
```bash
cd /home/qiuyanlong/worespace/by-claw-poc-linux/poc && chmod +x scripts/*.sh && ./scripts/build-version.sh 1.0.0
```
Expected: `dist-electron/linux-unpacked/` created, `packages/byclaw_1.0.0_amd64.deb` built, verify prints OK for #2-5.

- [ ] **Step 5: Build 1.1.0**

Run: `./scripts/build-version.sh 1.1.0`
Expected: `packages/byclaw_1.1.0_amd64.deb` built; six-place verify OK.

- [ ] **Step 6: Commit**

```bash
git add poc/electron-app/electron-builder.yml poc/packaging poc/scripts/build-version.sh poc/scripts/verify-versions.sh poc/scripts/make-icon.sh
git commit -m "feat(byclaw): two-layer packaging (electron-builder --dir -> dpkg-deb) + version consistency check"
```

---

## Phase 5 — AppArmor (implemented in §4.2; verify in validation)

The profile is written in Task 4.2 Step 7. Real verification (parser + `aa-status` + Wayland session) happens in Cases 6/7 (Phase 9). If the userns profile fails to parse or the app can't start under it, Case 7 is marked **FAIL** and the profile is corrected only after confirming the subject path matches the real binary (spec §13.10). No silent switch to SUID.

---

## Phase 6 — Aptly repo + policy service + HTTP server

### Task 6.1: aptly.conf (fixed rootDir, filesystem endpoint)

**Files:** Create `poc/apt-repository/aptly.conf`

- [ ] **Step 1: Write config**

```json
{
  "rootDir": "/home/qiuyanlong/worespace/by-claw-poc-linux/poc/apt-repository/aptly-db",
  "architectures": ["amd64"],
  "gpgProvider": "gpg2",
  "gpgDisableSign": false,
  "skipContents": true,
  "FileSystemPublishEndpoints": {
    "local": {
      "rootDir": "/home/qiuyanlong/worespace/by-claw-poc-linux/poc/apt-repository/aptly-db/public",
      "linkMethod": "copy"
    }
  }
}
```

> Fixed absolute rootDir (not `${HOME}`); fixed GNUPGHOME set via env in scripts; `-config=` always passed (spec §14).

### Task 6.2: setup-repo.sh (fixed normal user, no || true, nonzero exit)

**Files:** Create `poc/scripts/setup-repo.sh`

- [ ] **Step 1: Write script**

```bash
#!/usr/bin/env bash
# Run as a FIXED NORMAL USER (not root). Creates byclaw-poc aptly repo + GPG key.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/apt-repository"
CONF="$REPO/aptly.conf"
GNUPGHOME="$REPO/gpg-home"
APTLY="aptly -config=$CONF"

[ "$(id -u)" -ne 0 ] || { echo "ERROR: run as normal user, not root"; exit 1; }
mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"

# GPG key (fixed GNUPGHOME, not user ~/.gnupg) (spec §14.2)
if ! GNUPGHOME="$GNUPGHOME" gpg --list-keys byclaw-poc@localhost >/dev/null 2>&1; then
  GNUPGHOME="$GNUPGHOME" gpg --batch --gen-key <<KEY
%no-protection
Key-Type: RSA
Key-Length: 2048
Name-Real: Byclaw POC
Name-Email: byclaw-poc@localhost
Expire-Date: 0
%commit
KEY
fi
GPG_KEY="$(GNUPGHOME="$GNUPGHOME" gpg --list-keys --with-colons byclaw-poc@localhost | grep '^fpr' | head -1 | cut -d: -f10)"
[ -n "$GPG_KEY" ] || { echo "ERROR: no GPG key"; exit 1; }
export GNUPGHOME GPG_KEY
GNUPGHOME="$GNUPGHOME" gpg --armor --export byclaw-poc@localhost > "$REPO/byclaw-poc-public.gpg"

# aptly repo (fixed normal user only; no || true; nonzero exit on failure) (spec §14.1, §14.3)
if ! $APTLY repo show byclaw-poc >/dev/null 2>&1; then
  $APTLY repo create -distribution=noble -component=main byclaw-poc
fi
# initial empty publish (creates InRelease)
if ! $APTLY publish list | grep -q byclaw-poc; then
  $APTLY publish repo -origin=Lenovo -label=Byclaw -distribution=noble -component=main \
    --gpg-key="$GPG_KEY" --batch --passphrase="" -skip-contents=true byclaw-poc filesystem:local:
fi
echo "[setup-repo] OK; GPG key: $GPG_KEY"
```

### Task 6.3: publish-byclaw.sh + set-update-policy.sh + serve-repo.sh

**Files:** Create `poc/scripts/publish-byclaw.sh`, `poc/scripts/set-update-policy.sh`, `poc/scripts/serve-repo.sh`

- [ ] **Step 1: `publish-byclaw.sh <version>` (normal user)**

```bash
#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?version}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/apt-repository"; CONF="$REPO/aptly.conf"; GNUPGHOME="$REPO/gpg-home"
APTLY="aptly -config=$CONF"
export GNUPGHOME
GPG_KEY="$(GNUPGHOME="$GNUPGHOME" gpg --list-keys --with-colons byclaw-poc@localhost | grep '^fpr' | head -1 | cut -d: -f10)"

$APTLY repo add byclaw-poc "$ROOT/packages/byclaw_${VERSION}_amd64.deb"
if $APTLY publish list | grep -q byclaw-poc; then
  $APTLY publish update noble filesystem:local: --gpg-key="$GPG_KEY" --batch --passphrase="" -skip-contents=true
else
  $APTLY publish repo -origin=Lenovo -label=Byclaw -distribution=noble -component=main \
    --gpg-key="$GPG_KEY" --batch --passphrase="" -skip-contents=true byclaw-poc filesystem:local:
fi

# verify APT Packages index Version = VERSION (spec §12.3 #6, post-publish)
PV="$(python3 -c "import gzip,sys;print([l.split(': ',1)[1] for l in gzip.open('$REPO/aptly-db/public/dists/noble/main/binary-amd64/Packages.gz').read().decode().split('\n') if l.startswith('Version')][0])")"
[ "$PV" = "$VERSION" ] || { echo "ERROR: APT Packages Version=$PV != $VERSION"; exit 1; }
echo "[publish] byclaw $VERSION published; Packages Version OK"
```

- [ ] **Step 2: `set-update-policy.sh {none|optional|force}` (spec §8.2)**

```bash
#!/usr/bin/env bash
set -euo pipefail
MODE="${1:?none|optional|force}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$ROOT/apt-repository/aptly-db/public"
CURRENT="$(python3 -c "import json;print(json.load(open('$PUB/update-policy.json'))['latestVersion'])")"
case "$MODE" in
  none)     LATEST="$CURRENT"; MODE_VAL="optional" ;;
  optional) LATEST="${2:-1.1.0}"; MODE_VAL="optional" ;;
  force)    LATEST="${2:-1.1.0}"; MODE_VAL="force" ;;
  *) echo "usage: set-update-policy.sh {none|optional|force} [latestVersion]"; exit 1 ;;
esac
cat > "$PUB/update-policy.json" <<EOF
{
  "product": "byclaw",
  "channel": "stable",
  "latestVersion": "${LATEST}",
  "minimumSupportedVersion": "1.0.0",
  "mode": "${MODE_VAL}",
  "releaseNotes": ["Byclaw ${LATEST} (${MODE_VAL})"]
}
EOF
echo "[policy] mode=${MODE_VAL} latestVersion=${LATEST}"
```

- [ ] **Step 3: `serve-repo.sh {start|status|stop}` (127.0.0.1, PID+log; spec §8.4, §14.6)**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PUB="$ROOT/apt-repository/aptly-db/public"
PIDF="$ROOT/apt-repository/.server.pid"
LOGF="$ROOT/logs/serve-repo.log"
PORT=8099
case "${1:-status}" in
  start)
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then echo "already running $(cat "$PIDF")"; exit 0; fi
    mkdir -p "$(dirname "$LOGF")"
    cd "$PUB"
    nohup python3 -m http.server --bind 127.0.0.1 "$PORT" > "$LOGF" 2>&1 &
    echo $! > "$PIDF"
    sleep 1
    curl -fsS "http://127.0.0.1:${PORT}/dists/noble/InRelease" >/dev/null && echo "started pid=$(cat "$PIDF")" || { echo "ERROR: InRelease unreachable"; exit 1; }
    ;;
  status)
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then echo "running pid=$(cat "$PIDF")"; else echo "stopped"; fi
    curl -fsS "http://127.0.0.1:${PORT}/update-policy.json" >/dev/null 2>&1 && echo "policy: ok" || echo "policy: unreachable"
    ;;
  stop)
    [ -f "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null || true; rm -f "$PIDF"; echo "stopped"
    ;;
esac
```

- [ ] **Step 4: Run setup + publish 1.0.0 + serve (normal user)**

```bash
cd /home/qiuyanlong/worespace/by-claw-poc-linux/poc
./scripts/setup-repo.sh
./scripts/publish-byclaw.sh 1.0.0
./scripts/serve-repo.sh start
./scripts/serve-repo.sh status
```
Expected: repo created, 1.0.0 published (Packages Version OK), server running, policy reachable.

- [ ] **Step 5: Commit**

```bash
git add poc/apt-repository/aptly.conf poc/scripts/setup-repo.sh poc/scripts/publish-byclaw.sh poc/scripts/set-update-policy.sh poc/scripts/serve-repo.sh
git commit -m "feat(byclaw): aptly repo (fixed rootDir/GNUPGHOME, -config=, no ||true) + policy + http server"
```

---

## Phase 7 — unattended-upgrades + systemd + client-config (root install)

### Task 7.1: client-config package + systemd units + install-client-config.sh

**Files:**
- Create: `poc/client-config/byclaw-poc-repo-config/DEBIAN/{control,postinst}`
- Create: `poc/client-config/byclaw-poc-repo-config/etc/apt/sources.list.d/byclaw-poc.sources`
- Create: `poc/client-config/byclaw-poc-repo-config/etc/apt/apt.conf.d/60byclaw-poc-upgrades`
- Create: `poc/systemd/byclaw-poc-upgrade.service`, `.timer`
- Create: `poc/scripts/install-client-config.sh` (root, run by user)

- [ ] **Step 1: `byclaw-poc.sources` (deb822, Signed-By; spec §15)**

```
Types: deb
URIs: http://127.0.0.1:8099/
Suites: noble
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/byclaw-poc.gpg
```

- [ ] **Step 2: `60byclaw-poc-upgrades` (whitelist + blacklist; spec §14.8)**

```
Unattended-Upgrade::Allowed-Origins { "Lenovo:noble"; };
Unattended-Upgrade::Package-Whitelist { "^byclaw$"; };
Unattended-Upgrade::Package-Blacklist { "unrelated-poc"; "random-test-poc"; };
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
```

- [ ] **Step 3: systemd units (reuse pattern; spec §15)**

`byclaw-poc-upgrade.service`:
```ini
[Unit]
Description=Byclaw POC Auto-Upgrade Service
Documentation=https://github.com/qiuyanlong16/electron-updagre-for-ubuntu-24-poc

[Service]
Type=oneshot
ExecStart=/usr/bin/unattended-upgrade -v
Nice=19
IOSchedulingClass=idle
```
`byclaw-poc-upgrade.timer`:
```ini
[Unit]
Description=Byclaw POC Auto-Upgrade Timer (every 2 minutes, POC)

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
AccuracySec=10s
Unit=byclaw-poc-upgrade.service

[Install]
WantedBy=timers.target
```

- [ ] **Step 4: `install-client-config.sh` (ROOT; explains changes, pauses — run by user with sudo)**

```bash
#!/usr/bin/env bash
# ROOT script: installs keyring + sources + unattended config + systemd units.
# The user reviews this, then runs:  sudo ./scripts/install-client-config.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root (sudo ./scripts/install-client-config.sh)"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/apt-repository"
echo ">> Install repo public key to /usr/share/keyrings/byclaw-poc.gpg (0644)"
install -D -m 0644 "$REPO/byclaw-poc-public.gpg" /usr/share/keyrings/byclaw-poc.gpg
echo ">> Install APT source /etc/apt/sources.list.d/byclaw-poc.sources"
install -D -m 0644 "$ROOT/client-config/byclaw-poc-repo-config/etc/apt/sources.list.d/byclaw-poc.sources" /etc/apt/sources.list.d/byclaw-poc.sources
echo ">> Install unattended-upgrades config /etc/apt/apt.conf.d/60byclaw-poc-upgrades"
install -D -m 0644 "$ROOT/client-config/byclaw-poc-repo-config/etc/apt/apt.conf.d/60byclaw-poc-upgrades" /etc/apt/apt.conf.d/60byclaw-poc-upgrades
echo ">> Install + enable systemd timer"
install -D -m 0644 "$ROOT/systemd/byclaw-poc-upgrade.service" /etc/systemd/system/byclaw-poc-upgrade.service
install -D -m 0644 "$ROOT/systemd/byclaw-poc-upgrade.timer" /etc/systemd/system/byclaw-poc-upgrade.timer
systemctl daemon-reload
systemctl enable --now byclaw-poc-upgrade.timer
echo ">> apt-get update"
apt-get update
echo "[install-client-config] done"
```

- [ ] **Step 5: Commit**

```bash
git add poc/client-config poc/systemd poc/scripts/install-client-config.sh
git commit -m "feat(byclaw): client repo-config + systemd timer + root install script"
```

---

## Phase 8 — Full Vitest suite (spec §18.1, ten cases)

### Task 8.1: Ensure all ten Vitest cases exist

**Files:** `poc/electron-app/tests/{semver,state-machine,update-service}.test.ts` (created in Phase 1)

- [ ] **Step 1: Audit the 10 required cases against tests**

The 10 required (spec §18.1):
1. 1.0.0 vs 1.0.0 → LATEST ✓ (state-machine test 1)
2. running 1.0.0, latest 1.1.0, installed 1.0.0 → UPDATE_AVAILABLE ✓ (test 2)
3. running 1.0.0, installed 1.1.0, optional → READY_OPTIONAL ✓ (test 3)
4. running 1.0.0, installed 1.1.0, force → READY_FORCE ✓ (test 4)
5. 1.10.0 vs 1.9.0 ✓ (semver + state-machine test 5)
6. state file missing → fallback + stateSource=fallback ✓ (update-service test 1 uses corrupt; add a missing-file case)
7. state file corrupt → fallback ✓ (update-service test 1)
8. policy timeout → ERROR, no freeze ✓ (update-service test 2)
9. repeated check → dedup ✓ (update-service test 3)
10. repeated restart → dedup — add test

- [ ] **Step 2: Add missing-file + restart-dedup tests to `update-service.test.ts`**

```ts
it('missing state file -> fallback', async () => {
  const svc = new UpdateService({
    readStateFile: async () => { const e: any = new Error('ENOENT'); e.code='ENOENT'; throw e; },
    runningVersion: '1.0.0',
    fetchPolicy: async () => ({ latestVersion: '1.0.0', mode: 'optional' } as any),
  });
  const s = await svc.compute();
  expect(s.stateSource).toBe('fallback');
  expect(s.installedVersion).toBe('1.0.0');
});
```

For restart dedup: the restart path is in main (`app.relaunch`), not the pure service. Add an integration-style test that `restartApplication` IPC is invoked once by disabling the button — covered by UI behavior in Case 17; unit-test the `restart()` dedup in the composable via a flag. Add to a new `tests/restart-dedup.test.ts` mocking window.byclawAPI.

- [ ] **Step 3: Run full suite**

Run: `cd poc/electron-app && npx vitest run`
Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add poc/electron-app/tests
git commit -m "test(byclaw): complete vitest suite (spec §18.1 10 cases)"
```

---

## Phase 9 — 18 Case validation scripts (spec §17.2)

### Task 9.1: case-01 … case-18 + run-all-cases.sh

**Files:** Create `poc/tests-v2/case-01.sh` … `case-18.sh`, `run-all-cases.sh`, `screenshot.sh`, `evidence-v2/`

Each case writes a verdict file `poc/evidence-v2/case-NN.verdict` (PASS/FAIL/NOT TESTED) + logs. Root-dependent cases print the exact root commands and pause (the user runs them with sudo and saves outputs to `evidence-v2/`).

- [ ] **Step 1: `run-all-cases.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EV="$ROOT/evidence-v2"; mkdir -p "$EV"
for i in $(seq -w 1 18); do
  echo "=== Case $i ==="
  bash "$ROOT/tests-v2/case-$i.sh" 2>&1 | tee "$EV/case-$i.log"
done
echo "=== Summary ==="
for i in $(seq -w 1 18); do
  v="$(cat "$EV/case-$i.verdict" 2>/dev/null || echo NOT-TESTED)"
  printf 'Case %s: %s\n' "$i" "$v"
done
```

- [ ] **Step 2: Case scripts (complete, concise)**

`case-01.sh` (build two DEBs, normal user):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"; mkdir -p "$EV"
bash "$ROOT/scripts/build-version.sh" 1.0.0 2>&1 | tee "$EV/case-01-build-1.0.0.log"
bash "$ROOT/scripts/build-version.sh" 1.1.0 2>&1 | tee "$EV/case-01-build-1.1.0.log"
[ -f "$ROOT/packages/byclaw_1.0.0_amd64.deb" ] && [ -f "$ROOT/packages/byclaw_1.1.0_amd64.deb" ] \
  && echo PASS > "$EV/case-01.verdict" || echo FAIL > "$EV/case-01.verdict"
```

`case-02.sh` (install + /opt not user-writable; ROOT):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT steps required. Review and run with sudo:"; echo "  sudo dpkg -i $ROOT/packages/byclaw_1.0.0_amd64.deb"
echo "Then this case checks perms as normal user."
if [ ! -d /opt/lenovo/byclaw ]; then echo NOT-TESTED > "$EV/case-02.verdict"; exit 0; fi
stat -c '%U:%G %a' /opt/lenovo/byclaw | tee "$EV/case-02-stat.txt"
if ( echo x > /opt/lenovo/byclaw/.write-test 2>/dev/null ); then echo FAIL > "$EV/case-02.verdict"; rm -f /opt/lenovo/byclaw/.write-test; else echo PASS > "$EV/case-02.verdict"; fi
```

`case-03.sh` (new user sees app; OEM no Home pollution; ROOT creates user + normal checks):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
USER=byclaw-testuser
echo "ROOT steps: sudo useradd -m -s /bin/bash $USER ; verify /home/$USER has NO lenovo/byclaw before first run"
if ! id $USER >/dev/null 2>&1; then echo NOT-TESTED > "$EV/case-03.verdict"; exit 0; fi
if [ -d /home/$USER/.config/lenovo/byclaw ]; then echo "FAIL: Home polluted pre-run" | tee "$EV/case-03.txt"; echo FAIL > "$EV/case-03.verdict"; exit 0; fi
[ -f /usr/share/applications/com.lenovo.byclaw.desktop ] && echo PASS > "$EV/case-03.verdict" || echo FAIL > "$EV/case-03.verdict"
```

`case-04.sh` (Electron runs as normal user):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
# launch as the test user in the real session; capture ps uid
DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$(id -u byclaw-testuser 2>/dev/null || echo 1000) \
  su - byclaw-testuser -c "/opt/lenovo/byclaw/byclaw --no-sandbox=false &" 2>/dev/null || true
sleep 3
ps -eo user,pid,args | grep -E 'byclaw|electron' | grep -v grep | tee "$EV/case-04-ps.txt"
if grep -q "^byclaw-testuser" "$EV/case-04-ps.txt"; then echo PASS > "$EV/case-04.verdict"; else echo NOT-TESTED > "$EV/case-04.verdict"; fi
```

`case-05.sh` (preload/IPC isolation; normal user code check + runtime):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
# code-level: preload exposes only 5 methods; no fs/child_process
grep -RE 'exposeInMainWorld' "$ROOT/electron-app/src/preload" | tee "$EV/case-05-preload.txt"
grep -RSE 'require\(.child_process|require\(.fs|ipcRenderer\b[^.]' "$ROOT/electron-app/src/preload" && echo FAIL > "$EV/case-05.verdict" || echo PASS > "$EV/case-05.verdict"
```

`case-06.sh` (sandbox, no --no-sandbox; normal user runtime):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
ps -eo pid,args | grep -E 'byclaw|electron' | grep -v grep | tee "$EV/case-06-ps.txt"
if grep -q -- '--no-sandbox' "$EV/case-06-ps.txt"; then echo FAIL > "$EV/case-06.verdict"; else echo PASS > "$EV/case-06.verdict"; fi
```

`case-07.sh` (minimal AppArmor enforce; ROOT reload + aa-status):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT steps: sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw ; sudo aa-status"
if ! command -v aa-status >/dev/null 2>&1; then echo NOT-TESTED > "$EV/case-07.verdict"; exit 0; fi
sudo -n aa-status 2>/dev/null | grep -i byclaw | tee "$EV/case-07-aa-status.txt" || { echo NOT-TESTED > "$EV/case-07.verdict"; exit 0; }
# minimality: no banned caps in profile
if grep -E 'sys_admin|sys_chroot|dac_read_search|setuid|setgid|fowner|chown' /etc/apparmor.d/com.lenovo.byclaw; then echo FAIL > "$EV/case-07.verdict"; else echo PASS > "$EV/case-07.verdict"; fi
```

`case-08.sh` (APT signed + signed-by; ROOT):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
grep -q 'Signed-By' /etc/apt/sources.list.d/byclaw-poc.sources 2>/dev/null && echo PASS > "$EV/case-08.verdict" || echo NOT-TESTED > "$EV/case-08.verdict"
curl -fsS http://127.0.0.1:8099/dists/noble/InRelease 2>/dev/null | grep -i 'Origin\|Date' | tee "$EV/case-08-inrelease.txt" || true
```

`case-09.sh` (tamper rejected; ROOT):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT steps: append TAMPER to InRelease, then sudo apt-get update (expect NO_PUBKEY/badhash Fail)"
echo "  echo TAMPER | sudo tee -a $(curl -sI http://127.0.0.1:8099/dists/noble/InRelease >/dev/null; echo /var/.../InRelease) # see evidence for exact"
echo NOT-TESTED > "$EV/case-09.verdict"  # set PASS/FAIL after user runs + captures apt error
```

`case-10.sh` (only byclaw upgraded, no sudo; ROOT):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT steps: sudo systemctl start byclaw-poc-upgrade.service ; check dpkg.log upgrades byclaw only"
echo NOT-TESTED > "$EV/case-10.verdict"
```

`case-11.sh` (not-running upgrade -> next launch new; ROOT + normal):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "ROOT: ensure app stopped; sudo ./scripts/publish-byclaw.sh 1.1.0 (as user) ; sudo systemctl start byclaw-poc-upgrade.service"
echo "Normal: launch byclaw, read version, expect 1.1.0"
echo NOT-TESTED > "$EV/case-11.verdict"
```

`case-12.sh` (running upgrade, no exit, detects install; ROOT + normal):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "Normal: launch 1.0.0, note PID; ROOT: trigger upgrade to 1.1.0; assert PID alive + UI shows READY_OPTIONAL/READY_FORCE"
echo NOT-TESTED > "$EV/case-12.verdict"
```

`case-13.sh` (check version, no-update msg; normal):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
bash "$ROOT/scripts/set-update-policy.sh none"
DISPLAY=:0 su - byclaw-testuser -c "/opt/lenovo/byclaw/byclaw &" 2>/dev/null || true
sleep 3; bash "$ROOT/tests-v2/screenshot.sh" "$EV/case-13-latest.png"
# read window title / DOM via... no DevTools automation; assert via screenshot + log
echo "Manually verify '当前已是最新版本' shown; screenshot saved." | tee "$EV/case-13.txt"
echo NOT-TESTED > "$EV/case-13.verdict"  # flip to PASS after visual confirm
```

`case-14.sh` (new ver not installed, no apt call; normal):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
bash "$ROOT/scripts/set-update-policy.sh optional 1.1.0"
# assert no apt/dpkg in app process args; state == UPDATE_AVAILABLE
grep -c 'UPDATE_AVAILABLE' "$EV/case-12.txt" 2>/dev/null || true
echo NOT-TESTED > "$EV/case-14.verdict"
```

`case-15.sh` (optional 稍后/立即; normal): set-policy optional + write update-state.json installedVersion=1.1.0 (ROOT) + screenshot:
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
bash "$ROOT/scripts/set-update-policy.sh optional 1.1.0"
echo "ROOT: write /var/lib/lenovo/byclaw/update-state.json installedVersion=1.1.0 (run the provided snippet)"
echo NOT-TESTED > "$EV/case-15.verdict"
```

`case-16.sh` (force freeze; normal): set-policy force + installedVersion=1.1.0 (ROOT) + screenshot:
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
bash "$ROOT/scripts/set-update-policy.sh force 1.1.0"
echo "ROOT: ensure update-state.json installedVersion=1.1.0; Normal: screenshot READY_FORCE dialog"
echo NOT-TESTED > "$EV/case-16.verdict"
```

`case-17.sh` (restart -> new version + single instance; normal):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
echo "Normal: click 立即重启; assert new process shows 1.1.0; second launch refused by single-instance lock"
echo NOT-TESTED > "$EV/case-17.verdict"
```

`case-18.sh` (config/model preserved + offline runs; ROOT + normal):
```bash
#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
USER=byclaw-testuser
# SHA256 before/after (spec §11.3)
sha256sum /home/$USER/.config/lenovo/byclaw/last-run.json 2>/dev/null | tee "$EV/case-18-sha-pre.txt" || true
echo "ROOT: trigger upgrade; Normal: sha256 after, must match pre"
echo "Offline: stop serve-repo; launch app; must still run"
echo NOT-TESTED > "$EV/case-18.verdict"
```

`screenshot.sh`:
```bash
#!/usr/bin/env bash
OUT="${1:?out.png}"; DISPLAY=:0 scrot -u "$OUT" 2>/dev/null || scrot "$OUT" 2>/dev/null || echo "screenshot failed"
```

- [ ] **Step 3: Commit**

```bash
git add poc/tests-v2 poc/evidence-v2
git commit -m "test(byclaw): 18-case validation scripts + screenshot harness"
```

---

## Phase 10 — Real validation execution + VALIDATION_REPORT_V2

This phase runs after plan approval. Normal-user parts run automatically; root parts pause for the user per §17.3.

### Task 10.1: Run normal-user cases + capture screenshots

- [ ] **Step 1: Save session type evidence**

```bash
echo "$XDG_SESSION_TYPE" > poc/evidence-v2/xdg-session-type.txt   # expect: wayland
```

- [ ] **Step 2: Run Cases 1,5,6,13–17 (normal-user parts)**; capture screenshots (4 required: 1.0.0 main, optional dialog, force dialog, restart-to-1.1.0). Mark NOT TESTED where a root prerequisite wasn't met.

- [ ] **Step 3: Prepare exact root command scripts for Cases 2,3,4,7,8,9,10,11,12,18; present to user; pause.**

For each: explain which system files change, then wait. After the user runs with `sudo` and saves outputs to `poc/evidence-v2/`, read them and set verdicts.

### Task 10.2: Write VALIDATION_REPORT_V2.md

- [ ] **Step 1: Generate the report** with all 18 Cases (prereq/command/actual result/log evidence/screenshot/PASS|FAIL|NOT TESTED), the four screenshots, the `echo $XDG_SESSION_TYPE` evidence, and the final 5 acceptance answers (spec §14 final). Mark unexecuted root Cases NOT TESTED. Keep old `VALIDATION_REPORT.md` untouched; describe it as "报告与证据不一致，因此结果不可采信".

- [ ] **Step 2: Commit**

```bash
git add poc/VALIDATION_REPORT_V2.md poc/evidence-v2
git commit -m "docs(byclaw): VALIDATION_REPORT_V2 with real evidence (18 cases)"
```

---

## Phase 11 — Docs + changelog

### Task 11.1: README + deployment contract + file changelog

- [ ] **Step 1: Update `README.md` / `README.zh-CN.md`** — bilingual toggle, byclaw architecture, build/validate commands, 18 Cases, reproducibility-first. Keep `poc/README.md` deep-dive updated to byclaw/Vue3.

- [ ] **Step 2: `docs/deployment/private-apt-contract.md`** — HTTPS, key rotation, Origin/Label, Allowed-Origins, Packages index fields, Hash verification, POC-vs-prod differences (spec §14.10).

- [ ] **Step 3: `docs/byclaw-file-changelog.md`** — file-level modification list (new/modified/kept).

- [ ] **Step 4: Commit + push branch**

```bash
git add README.md README.zh-CN.md poc/README.md docs/deployment docs/byclaw-file-changelog.md
git commit -m "docs(byclaw): update READMEs, deployment contract, file changelog"
git push -u origin feat/byclaw-vue3-redesign
```

---

## Self-Review (run after writing)

**Spec coverage:**
- §2 confirmed defects D1–D5 → Tasks 4.2 (D1,D2), 4.2/13 (D3), 6.1/6.2 (D4), V2 report (D5). ✓
- §3 naming → all tasks use byclaw paths. ✓
- §4 architecture → Phase 4 + 6 + 7. ✓
- §5 Vue UI → Phase 3. ✓
- §6 preload/main security → Task 2.1/2.3. ✓
- §7 state model → Phase 1. ✓
- §8 policy service → Task 6.3. ✓
- §9 postinst atomic → Task 4.2 Step 2. ✓
- §10 restart → Task 2.3. ✓
- §11 first-run → Task 3.4. ✓
- §12 two-layer + six-place → Task 4.3. ✓
- §13 AppArmor userns → Task 4.2 Step 7 + Phase 5. ✓
- §14 aptly fixes → Phase 6. ✓
- §15 unattended/systemd → Phase 7. ✓
- §16 security list → enforced across tasks; runtime-checked in Cases. ✓
- §17 18 Cases → Phase 9/10. ✓
- §18 Vitest → Phase 8. ✓

**Placeholder scan:** App.vue `onMounted` had a placeholder for lastSeen — resolved in Task 3.4. No remaining TBDs.

**Type consistency:** `UpdateState.upgradedFrom?` added in 3.4 and read in App.vue 3.3 — consistent. `computeState` `StateInput.releaseNotes` threaded in Task 1.4/1.5 — consistent. `byclawAPI` 5 methods used consistently in preload/composable.

**Risks to flag in V2:** AppArmor userns may need real-session iteration (Case 7 may go FAIL→fix→PASS); GUI automation has no DevTools driver, so Cases 13–17 rely on `scrot` screenshots + manual visual confirm (NOT TESTED until visually confirmed per spec §17.4).
