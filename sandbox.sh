#!@bashPath@
set -euo pipefail

# nixos-sandbox: run <command> inside a bubblewrap sandbox on NixOS.
#
# Filesystem policy
#   * / is mounted read-only. Because the sandbox keeps your uid/gid, reads
#     are limited to what the current user can read on the host.
#   * writable inside the sandbox:
#       - the working directory (or the directory given with -w/--write)
#       - /tmp (tmpfs, discarded on exit)
#       - the cache dir (~/.cache), so any tool's cache works
#       - the nix daemon socket, the user's per-user store dirs, and the nix
#         state dir (~/.local/state/nix), so nix tooling works no matter which
#         command is run
#   * $HOME and $XDG_RUNTIME_DIR are otherwise read-only: nothing may be
#     written there persistently except the nix cache/state above; everything
#     else must live in the working directory.
#
# All programs of the nix store are available: the common nix profile
# locations (current-system, default profile, per-user profiles, ~/.nix-profile)
# are prepended to PATH.

BWRAP="@bwrapPath@"

WRITE_DIRS=()
SHARE_NET=0

usage() {
  cat >&2 <<'EOF'
usage: sandbox [options] <command> [args...]

Run <command> inside a bubblewrap sandbox.

Options:
  -w, --write DIR   make DIR writable inside the sandbox (repeatable)
  --net             share the host network (default: network is blocked)
  -h, --help        show this help

Environment:
  SANDBOX_WRITE     extra writable directories, colon-separated
  SANDBOX_CWD       directory to make writable instead of the current one

$HOME and $XDG_RUNTIME_DIR are always read-only inside the sandbox; persistent
state must live in the working directory.
EOF
}

# Never make a whole system-managed root writable. We only protect the roots
# themselves (and a couple of broad store trees): bwrap's `--bind dir dir`
# remounts just that one path read-write and leaves its siblings read-only, so
# a specific subdirectory -- e.g. a working directory under /var/lib/hermes
# or /home/<user> -- is safe to make writable. This matches the documented
# contract: "persistent state must live in the working directory", even when
# that working directory happens to sit inside $HOME.
is_protected_path() {
  local p
  p="$1"
  p="${p%/}"
  [[ -z "$p" ]] && p="/"
  case "$p" in
    /|/nix/store|/nix/var|/etc|/usr|/run|/proc|/sys|/dev|/bin|/sbin|/lib|/lib64|/boot|/opt|/root|/tmp|/var|/home)
      return 0 ;;
  esac
  return 1
}

add_write_dir() {
  local d
  d="$(readlink -f -- "$1" 2>/dev/null || printf '%s' "$1")"
  if [[ ! -d "$d" ]]; then
    printf 'sandbox: warning: %s is not a directory, skipping\n' "$1" >&2
    return
  fi
  if is_protected_path "$d"; then
    printf 'sandbox: warning: refusing to make %s writable, skipping\n' "$d" >&2
    return
  fi
  WRITE_DIRS+=("$d")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -w|--write) shift; [[ $# -gt 0 ]] || { usage; exit 1; }; add_write_dir "$1"; shift ;;
    --net) SHARE_NET=1; shift ;;
    --) shift; break ;;
    -*) printf 'sandbox: unknown option: %s\n' "$1" >&2; usage; exit 1 ;;
    *) break ;;
  esac
done

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

PROG="$1"
shift

export HOME="${HOME:-/root}"
export USER="${USER:-$(id -un)}"
export LOGNAME="$USER"

if [[ -z "${SANDBOX_CWD:-}" ]]; then
  SANDBOX_CWD="$PWD"
fi
add_write_dir "$SANDBOX_CWD"

if [[ -n "${SANDBOX_WRITE:-}" ]]; then
  IFS=':' read -r -a _extra <<< "$SANDBOX_WRITE"
  for d in "${_extra[@]}"; do
    [[ -n "$d" ]] && add_write_dir "$d"
  done
fi

# Make the nix store's programs available.
_nix_bin=(
  /run/current-system/sw/bin
  /run/current-system/sw/sbin
  /nix/var/nix/profiles/default/bin
  /nix/var/nix/profiles/default/sbin
)
[[ -d "$HOME/.nix-profile/bin" ]] && _nix_bin+=("$HOME/.nix-profile/bin")
[[ -d "$HOME/.nix-profile/sbin" ]] && _nix_bin+=("$HOME/.nix-profile/sbin")
for _d in /nix/var/nix/profiles/per-user/*/bin; do
  [[ -d "$_d" ]] && _nix_bin+=("$_d")
done
export PATH="$(IFS=':'; printf '%s' "${_nix_bin[*]}"):$PATH"

args=(
  --unshare-all
  --die-with-parent
  --ro-bind / /
  --dev /dev
  --proc /proc
  --tmpfs /tmp
  --tmpfs /dev/shm
  --symlink /proc/self/fd /dev/fd
  --symlink /proc/self/fd/0 /dev/stdin
  --symlink /proc/self/fd/1 /dev/stdout
  --symlink /proc/self/fd/2 /dev/stderr
)

if [[ "$SHARE_NET" -eq 1 ]]; then
  args+=(--share-net)
fi

for d in "${WRITE_DIRS[@]}"; do
  args+=(--bind "$d" "$d")
done

# nix tooling talks to the nix daemon through the socket and keeps the user's
# own state under /nix/var/nix, so those paths must be writable no matter
# which command is run. Host permissions still apply, so a non-root user can
# only touch their own per-user dirs.
for d in \
  /nix/var/nix/daemon-socket \
  /nix/var/nix/gcroots/per-user/"$USER" \
  /nix/var/nix/profiles/per-user/"$USER"; do
  [[ -d "$d" ]] && args+=(--bind "$d" "$d")
done

# The cache dir (~/.cache) is writable so any tool's cache works, and the nix
# state dir (~/.local/state/nix, e.g. the fetcher cache used by flakes) is
# writable so nix tooling works. The rest of $HOME stays read-only. If a dir
# cannot be created in $HOME (or resolves to a protected system path), fall
# back to the ephemeral /tmp so tools still work.
_cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
_state_home="${XDG_STATE_HOME:-$HOME/.local/state}/nix"

_cache_ok=1
if ! is_protected_path "$_cache_home" && mkdir -p "$_cache_home" 2>/dev/null; then
  args+=(--bind "$_cache_home" "$_cache_home")
else
  _cache_ok=0
fi

_state_ok=1
if ! is_protected_path "$_state_home" && mkdir -p "$_state_home" 2>/dev/null; then
  args+=(--bind "$_state_home" "$_state_home")
else
  _state_ok=0
fi

if [[ $_cache_ok -eq 0 ]]; then
  export XDG_CACHE_HOME=/tmp/.nix-sandbox/cache
fi
if [[ $_state_ok -eq 0 ]]; then
  export XDG_STATE_HOME=/tmp/.nix-sandbox/state
fi

args+=(--chdir /)

# Re-enter the requested working directory inside the sandbox, creating it
# first if it lives on a tmpfs that does not exist in the sandbox (e.g. /tmp).
exec "$BWRAP" "${args[@]}" -- /bin/sh -c 'mkdir -p -- "$1" 2>/dev/null; cd "$1"; shift; exec "$@"' _ "$SANDBOX_CWD" "$PROG" "$@"
