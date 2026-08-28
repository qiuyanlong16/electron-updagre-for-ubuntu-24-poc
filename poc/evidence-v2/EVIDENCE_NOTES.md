# Real-run evidence notes (2026-08-28, Wayland desktop, branch feat/byclaw-vue3-redesign)

One real unattended-upgrade 1.1.0 -> 1.2.0 (`sudo systemctl start byclaw-poc-upgrade.service`,
post `apt-get update`) + operator click of 立即重启 covers most GUI/runtime cases.

| Case | Verdict | Real-run evidence |
|---|---|---|
| 06 sandbox | PASS | `case-06-14-ps-args.txt`: 9 byclaw procs, renderers `--enable-sandbox`, `--no-sandbox` hits=0, `app.asar` loaded |
| 10 only-byclaw | PASS | dpkg.log: `upgrade byclaw 1.1.0->1.2.0`; only triggers desktop-file-utils+gnome-menus (no unrelated UPGRADE); unattended whitelist `^byclaw$` |
| 11 next-launch new ver | PASS | post-upgrade restart loaded the 1.2.0 binary -> LATEST (operator-confirmed "already latest version") |
| 12 running detects | PASS | running 1.1.0 app (PID 321795) survived the upgrade; read installedVersion=1.2.0 via 5s poll -> showed READY_OPTIONAL; exited only on operator's restart click |
| 13 LATEST | PASS | running 1.2.0 == latest 1.2.0 -> LATEST; operator-confirmed "already latest version"; `case-13-latest.png` |
| 14 UPDATE_AVAILABLE no-apt | PASS | operator saw "found 1.2.0" toast, clicked 我知道了, nothing changed; `case-14-noapt.txt`=0 forbidden cmds; `case-14-update-available.png` |
| 15 READY_OPTIONAL | PASS | real upgrade -> running 1.1.0 saw installed 1.2.0 + mode optional -> READY_OPTIONAL; operator saw 稍后/立即 + clicked 立即重启; `case-15-optional.png` |
| 17 restart + single-inst | PASS | restart -> 1.2.0 LATEST; 2nd launch exit=0 (refused), 1st PID 327605 alive, one main proc |
| 18 config preserve | PASS | `case-18-sha-post.txt` == `case-18-sha-pre.txt` (a83325...); note: config.json is NOT a dpkg conffile but is byte-identical across 1.0.0/1.1.0/1.2.0 |

Pending (need sudo): **Case 16** (READY_FORCE, synthetic state per runbook), **Case 09** (tamper InRelease).

Lesson logged: the first post-sudo capture hit the upgrade mid-flight (service still
"activating") and momentarily showed stale 1.1.0; re-capture after `systemctl is-active=inactive
Result=success` gave the true 1.2.0 state. The mis-captured screenshot was quarantined as
`case-15-INVALID-*.png` (NOT used as Case-15 evidence).
