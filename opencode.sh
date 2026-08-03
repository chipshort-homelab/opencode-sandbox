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
auto=()
if [[ "${OPENCODE_SANDBOX_NO_AUTO:-0}" != "1" ]]; then
  auto=(--auto)
fi

exec @sandboxPath@ --net "${opts[@]}" -- @opencodePath@ "${auto[@]}" "$@"
