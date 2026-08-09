#!@bashPath@
set -euo pipefail

# opencode wrapper: run the real opencode inside the nixos-sandbox with
# network enabled. opencode creates these XDG dirs at startup; config, state
# and data are bound read-write and the cache dir (~/.cache) is already
# writable wholesale via the general sandbox. The rest of $HOME stays
# read-only.

# When cwd is a git linked worktree, git must write to the MAIN repo's .git
# dir, which lives outside cwd. Make that dir writable too; for a normal
# checkout the common dir is already under cwd (writable), so skip it.

dirs=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  "${XDG_STATE_HOME:-$HOME/.local/state}/opencode"
  "${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
)

opts=()
for d in "${dirs[@]}"; do
  mkdir -p "$d" 2>/dev/null || true
  opts+=(-w "$d")
done

# A linked git worktree stores its git data in the MAIN repo's .git dir, i.e.
# git's private dir is `<main>/.git/worktrees/<name>`, outside the worktree
# cwd (and therefore read-only inside the sandbox). Detect a linked worktree
# by `--git-dir` containing `/worktrees/` (true both at the worktree root and
# inside its subdirs; false for a normal checkout at any depth) and make the
# main repo's .git dir writable so git commands work there. When there is no
# git, or cwd is a normal checkout / bare subdirectory, this falls through
# harmlessly and never errors out the wrapper.
worktree_git="$(git rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
if [[ "$worktree_git" == */worktrees/* ]]; then
  common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -n "$common_dir" && "$common_dir" != "${PWD%/}/"* ]]; then
    opts+=(-w "$common_dir")
  fi
fi

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
