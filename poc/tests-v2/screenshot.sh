#!/usr/bin/env bash
# Wayland session — scrot captures XWayland windows (the Byclaw app runs via DISPLAY=:0 XWayland);
# native Wayland windows may not be captured. grim is not installed.
OUT="${1:?usage: screenshot.sh <out.png>}"; DISPLAY=:0 scrot -u "$OUT" 2>/dev/null || scrot "$OUT" 2>/dev/null || echo "screenshot failed"
