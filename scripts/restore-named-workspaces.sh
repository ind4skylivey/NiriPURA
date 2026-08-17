#!/usr/bin/env bash
# Pin named workspaces onto the primary bar monitor (DP-1).
#
# Why: open-on-output only applies when a named workspace is FIRST created.
# On cold boot, if DP-1 connects late, niri can place them on a secondary output (e.g. DP-2).
# Bar.default is only on DP-1 → LG would show plain numbered workspaces.
#
# IMPORTANT: This script does NOT touch Noctalia widget settings
# (hide_when_empty, max_label_chars, size, etc.). Those are yours —
# change them in the Noctalia UI; they stay as you leave them.
#
# Idempotent. Log: ~/.local/state/niri/restore-named-workspaces.log

set -euo pipefail

PRIMARY_OUTPUT="${NIRI_PRIMARY_OUTPUT:-DP-1}"
NIRI_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
WORKSPACES_KDL="${NIRI_CFG}/modules/workspaces.kdl"
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/niri/restore-named-workspaces.log"

mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "==== $(date -Iseconds) restore-named-workspaces start ===="

log() { echo "[$(date +%H:%M:%S)] $*"; }

ready=0
for i in $(seq 1 90); do
  if niri msg outputs >/dev/null 2>&1 \
    && niri msg outputs 2>/dev/null | grep -q "(${PRIMARY_OUTPUT})"; then
    ready=1
    break
  fi
  sleep 0.5
done

if [[ "$ready" -ne 1 ]]; then
  log "niri/primary not ready after wait — exit"
  exit 0
fi

if [[ ! -f "$WORKSPACES_KDL" ]]; then
  log "missing $WORKSPACES_KDL — exit"
  exit 0
fi

export PRIMARY_OUTPUT WORKSPACES_KDL

for pass in 1 2 3; do
  log "workspace pass $pass"
  python3 - <<'PY'
import json, os, re, subprocess, sys
from pathlib import Path

primary = os.environ["PRIMARY_OUTPUT"]
text = Path(os.environ["WORKSPACES_KDL"]).read_text(encoding="utf-8")
names = re.findall(r'workspace\s+"([^"]+)"', text)
if not names:
    sys.exit(0)

def run(args):
    r = subprocess.run(args, capture_output=True, text=True)
    return r.returncode == 0, (r.stderr or r.stdout or "").strip()

r = subprocess.run(["niri", "msg", "-j", "workspaces"], capture_output=True, text=True)
if r.returncode != 0:
    print("niri msg workspaces failed", file=sys.stderr)
    sys.exit(0)

ws = json.loads(r.stdout)
by_name = {w.get("name"): w for w in ws if w.get("name")}

moved = 0
for name in names:
    w = by_name.get(name)
    if not w:
        print(f"missing named ws: {name!r}")
        continue
    if w.get("output") != primary:
        ok, err = run(["niri", "msg", "action", "move-workspace-to-monitor",
                       "--reference", name, primary])
        print(f"move {name!r} -> {primary}: {'ok' if ok else err}")
        moved += 1

for i, name in enumerate(names, start=1):
    ok, err = run(["niri", "msg", "action", "move-workspace-to-index",
                   "--reference", name, str(i)])
    if not ok:
        print(f"index {i} {name!r}: {err}")

r = subprocess.run(["niri", "msg", "-j", "workspaces"], capture_output=True, text=True)
ws = json.loads(r.stdout) if r.returncode == 0 else []
wrong = [w for w in ws if w.get("name") and w.get("output") != primary]
print(f"moved={moved} wrong_after={len(wrong)}")
if wrong:
    for w in wrong:
        print(f"  still on {w.get('output')}: {w.get('name')!r}")
    sys.exit(2)
sys.exit(0)
PY
  rc=$?
  if [[ $rc -eq 0 ]]; then
    log "workspaces OK on $PRIMARY_OUTPUT"
    break
  fi
  log "pass $pass incomplete (rc=$rc), retry in 2s"
  sleep 2
done

log "final workspaces:"
niri msg workspaces || true
log "done (widget settings untouched)"
