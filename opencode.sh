#!@bashPath@
set -euo pipefail

# opencode wrapper: run the real opencode inside the nixos-sandbox with
# network enabled. opencode creates these four XDG dirs at startup, so they
# are bound read-write; the rest of $HOME stays read-only.

dirs=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  "${XDG_CACHE_HOME:-$HOME/.cache}/opencode"
  "${XDG_STATE_HOME:-$HOME/.local/state}/opencode"
  "${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
)

opts=()
for d in "${dirs[@]}"; do
  mkdir -p "$d" 2>/dev/null || true
  opts+=(-w "$d")
done

# Run without opencode's permission system: --auto auto-approves bash, edit,
# webfetch, ... requests that are not explicitly denied. Set
# OPENCODE_SANDBOX_NO_AUTO=1 to keep the normal permission prompts.
#
# opencode >= 1.18 rejects `--auto` when it precedes the `run` subcommand
# (it falls back to printing help and exiting 1). It must be attached after
# `run`:  opencode run --auto '<task>'. For other invocations (TUI, pr,
# serve, ...) keep it at the front as before.
oc_args=("$@")
if [[ "${OPENCODE_SANDBOX_NO_AUTO:-0}" != "1" ]]; then
  if [[ ${#oc_args[@]} -gt 0 && "${oc_args[0]}" == "run" ]]; then
    oc_args=(run --auto "${oc_args[@]:1}")
  else
    oc_args=(--auto "${oc_args[@]}")
  fi
fi

exec @sandboxPath@ --net "${opts[@]}" -- @opencodePath@ "${oc_args[@]}"
