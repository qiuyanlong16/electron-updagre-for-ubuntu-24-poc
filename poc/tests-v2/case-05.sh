#!/usr/bin/env bash
set -uo pipefail; ROOT="$(cd "$(dirname "$0")/.." && pwd)"; EV="$ROOT/evidence-v2"
# Verify preload IPC isolation (spec): contextBridge.exposeInMainWorld('byclawAPI', {...}) with
# exactly 5 methods; no require('child_process'/'fs'); no RAW ipcRenderer exposure to the renderer.
# Method calls like ipcRenderer.invoke/on inside contextBridge are legitimate, NOT a failure —
# the failure is exposing the RAW ipcRenderer object to the renderer.
PRE="$ROOT/electron-app/src/preload"
# -F fixed-string for the literal 'byclawAPI' exposure (portable, no regex paren ambiguity)
grep -RF "exposeInMainWorld('byclawAPI'" "$PRE" | tee "$EV/case-05-preload.txt"
# count method keys inside the exposeInMainWorld(...) block (expect exactly 5)
# ASSUMPTION: preload methods are flat — no one-line callback ending in '});' inside a method body,
# else awk exits early at the first '});' and undercounts (false FAIL). Current preload satisfies this.
MCOUNT="$(awk '/exposeInMainWorld/{f=1} f{print} /});/{if(f)exit}' "$PRE"/*.ts 2>/dev/null | grep -cE '^[[:space:]]+[a-zA-Z]+[[:space:]]*:' )"
echo "method count: ${MCOUNT:-0} (expect 5)" | tee -a "$EV/case-05-preload.txt"
# FAIL if forbidden: require child_process/fs, or RAW ipcRenderer exposure to the renderer
# (expose under name ipcRenderer, assign to window/globalThis, or use as a bare object value)
# -E ERE (not -S: -S is invalid in GNU grep; -RE keeps the check portable so it always runs)
if grep -RE "require\(['\"]child_process['\"]\)|require\(['\"]fs['\"]\)|exposeInMainWorld\(['\"]ipcRenderer|window\.ipcRenderer|globalThis\.ipcRenderer|:[[:space:]]*ipcRenderer[^.]" "$PRE" | tee "$EV/case-05-forbidden.txt"; then
  echo FAIL > "$EV/case-05.verdict"
elif ! grep -RqF "exposeInMainWorld('byclawAPI'" "$PRE"; then
  echo FAIL > "$EV/case-05.verdict"  # byclawAPI not exposed
elif [ "${MCOUNT:-0}" -ne 5 ]; then
  echo FAIL > "$EV/case-05.verdict"  # not exactly 5 methods
else
  echo PASS > "$EV/case-05.verdict"
fi
