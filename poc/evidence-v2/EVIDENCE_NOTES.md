# Real-run evidence notes (2026-08-28, Wayland desktop, branch feat/byclaw-vue3-redesign)

Two real unattended-upgrade cycles cover the core update path:
  - 1.1.0 -> 1.2.0 (mode=optional -> READY_OPTIONAL; operator click 立即重启 -> 1.2.0 LATEST)
  - 1.2.0 -> 1.3.0 (mode=force -> READY_FORCE frozen UI; operator restart -> 1.3.0)
(An earlier 1.0.0 -> 1.1.0 at 10:51 also ran; see case-11-dpkg-upgrade.txt for the full chain.)

| Case | Verdict | Real-run evidence |
|---|---|---|
| 06 sandbox | PASS | LIVE re-capture `case-06-14-ps-args.txt`: 8 byclaw procs; renderers `--enable-sandbox`; `--no-sandbox` hits=0; `app.asar` loaded; `case-06-ps.txt` now populated (was stale/empty) |
| 10 only-byclaw | PASS | RE-CAPTURED from /var/log/dpkg.log (`case-10-dpkglog-byclaw.txt`, 33 lines): upgrade byclaw 1.1.0->1.2.0 + 1.2.0->1.3.0; distinct-pkgs = {byclaw} upgraded + {desktop-file-utils, gnome-menus} trigproc only (no unrelated UPGRADE); unattended whitelist `^byclaw$` |
| 11 next-launch new ver | PASS | `case-11-evidence.txt` + `case-11-dpkg-upgrade.txt` (dpkg.log upgrade chain) + operator-confirmed LATEST screen `case-13-latest.png` |
| 12 running detects | PASS | `case-12-evidence.txt`: same real event as Case 15/16 — surviving process rendered READY_OPTIONAL (`case-15-optional.png`) / READY_FORCE (`case-16-force.png`) on the real installedVersion advance; postinst does NOT restart the process; 5s poll = main.ts:57 |
| 13 LATEST | PASS | `case-13-latest.png` (259 KB) + operator visual "already latest version"; dpkg.log configure byclaw 1.2.0 (12:47:25); policy latestVersion=1.2.0 at capture time. `case-13.txt` rewritten (was a stale "deferred" line) |
| 14 UPDATE_AVAILABLE no-apt | PASS | LIVE: `case-14-noapt.txt` = 0 forbidden cmds in byclaw args + `case-14-human-confirm.txt` (operator saw "发现 1.2.0" toast, clicked 我知道了, nothing changed) + `case-14-update-available.png` |
| 15 READY_OPTIONAL | PASS | real 1.1.0->1.2.0 upgrade -> surviving 1.1.0 saw installed 1.2.0 + mode optional -> READY_OPTIONAL; operator saw 稍后/立即 + clicked 立即重启; `case-15-optional.png` (mid-flight mis-capture quarantined as `case-15-INVALID-*.png`, NOT used) |
| 16 READY_FORCE | PASS | real 1.2.0->1.3.0 force upgrade (13:21) -> frozen force dialog; `case-16-force.png` + `case-16-journalctl.txt` (unattended-upgrade lifecycle) + operator visual in `case-16.verdict` |
| 17 restart + single-inst | PASS | LIVE RE-CAPTURE `case-17-single-instance.txt`: 2nd launch (env -u ELECTRON_RUN_AS_NODE, timeout 8s) exit=0 (lock refused), main PID 331958 survived, exactly 1 main proc; restart->1.3.0 backed by dpkg.log |
| 18 config preserve | PASS | RE-CAPTURED valid before/after via DEB extraction: `case-18-sha-pre.txt` (1.2.0 DEB config) == `case-18-sha-post.txt` (installed post-1.3.0) == a8332527...; `case-18-config-hashes.txt` shows all 4 DEBs + installed identical. Caveat: not a conffile; default-only preserved |

DONE (no longer pending): **Case 16** (real force upgrade 1.2.0->1.3.0, not synthetic), **Case 09** (tamper InRelease -> `BADSIG 8E461A79003247C0` rejected at 13:29; repo re-published/restored).

DONE — Case 03 home-pollution traversal: the operator ran `sudo bash -c 'ls -la
/home/byclaw-testuser/.config/lenovo/byclaw 2>&1; ls -la /home/byclaw-testuser/.config/byclaw 2>&1'`
(root-access mode). Result: `.config/lenovo/byclaw` = "没有那个文件或目录" (absent → no pollution);
`.config/byclaw` exists as the normal Electron user-data-dir (last-run.json, Cache, …) — expected
app data, not pollution. Both Case 03 halves verified → PASS. All 18 cases now closed (18/18).

Adversarial-verify (4-skeptic workflow wf_126d8497-3e9) re-checked all 18 verdicts. Its flagged
risks (03 home-pollution no-op [closed by root ls], 05 code-review-only, 10 empty evidence, 13
stale text, 17 notes-only single-instance, 18 invalid hash timestamps) are addressed above by
re-capture, root traversal, or honest scoping. See VALIDATION_REPORT_V2.md §6 for the folded findings.

Lesson logged: the first post-sudo capture hit the upgrade mid-flight (service still
"activating") and momentarily showed stale 1.1.0; re-capture after `systemctl is-active=inactive
Result=success` gave the true 1.2.0 state. The mis-captured screenshot was quarantined as
`case-15-INVALID-*.png` (NOT used as Case-15 evidence). Also: `grep` on /var/log/dpkg.log needs
`-a` (the file is detected as binary, so plain grep suppresses matches) — earlier empty greps
were a capture-tool artifact, not missing data.
