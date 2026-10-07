#!/usr/bin/env bash
# tab-restore: start a program again in the Ghostty tab or split where a
# Ghostty quit or a restart cut it off.
#
# Usage:
#   tab-restore note <name>  record that this tab or split runs <name>
#   tab-restore clear        forget it: the program returned on its own
#   tab-restore --restore    offer to start it again (shell startup)
#
# The root-owned shell startup (fish init, /etc/zdotdir/.zshrc) calls `note`
# before a command whose first word is a listed program, and `clear` once that
# command returns. `clear` keeps the record when the terminal is gone (see
# have_terminal), so a record survives only when a Ghostty quit or a restart
# cut the program off. Quitting the program yourself clears it, and the next
# shell asks nothing.
#
# One record per surface, keyed by GHOSTTY_SURFACE_ID (Ghostty patch
# surface-id; Ghostty saves the id with the window state, so a restored
# surface sees the same value):
#   $XDG_STATE_HOME/tab-restore/<SURFACE_ID>
#
# The record is user-writable, so it holds only a program name and is read as
# data: the name must be one of the programs listed in nix-config
# (tabRestore.programs), and what runs is that entry's store path, started
# without the arguments it had. A record naming anything else is dropped.

set -uo pipefail

uuid_re='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'

usage() {
  cat <<'EOF'
Usage:
  tab-restore note <name>  record that this tab or split runs <name>
  tab-restore clear        forget it: the program returned on its own
  tab-restore --restore    offer to start it again (shell startup)
EOF
}

# The listed programs (nix-config tabRestore.programs). Sets label and path;
# fails for any other name.
label='' path=''
program() {
  case "$1" in
@PROGRAMS@
    *) return 1 ;;
  esac
}

fail() {
  printf 'tab-restore: %s\n' "$1" >&2
  exit 1
}

surface=${GHOSTTY_SURFACE_ID:-}
dir="${XDG_STATE_HOME:-$HOME/.local/state}/tab-restore"
record="$dir/$surface"

need_surface() {
  [[ -n "$surface" ]] || fail "not in a Ghostty tab or split (GHOSTTY_SURFACE_ID is unset)"
  [[ "$surface" =~ $uuid_re ]] || fail "GHOSTTY_SURFACE_ID is not a UUID"
}

# Atomic: a temp file in the same folder, then rename.
note() {
  need_surface
  program "$1" || fail "not a listed program: $1"
  mkdir -p -- "$dir" || fail "cannot create $dir"
  local tmp
  tmp=$(mktemp "$dir/.$surface.XXXXXX") || fail "cannot write in $dir"
  if printf '%s\n' "$1" >"$tmp" && mv -f -- "$tmp" "$record"; then
    return 0
  fi
  rm -f -- "$tmp"
  fail "cannot write $record"
}

# Whether this process still has its terminal. Closing a tab or split, or
# quitting Ghostty, hangs up the terminal: Ghostty signals the tab's process
# group (src/termio/Exec.zig killPid), its session leader exits, and the
# kernel takes the terminal away from everything left in the session. Only
# then does a program in the foreground get the hangup, so by the time it
# returns, /dev/tty can no longer be opened. The exit status can't tell the
# two apart: WeeChat answers a hangup with /quit and exits 0 (measured
# 2026-10-07).
have_terminal() {
  { : </dev/tty; } 2>/dev/null
}

# Remove the record only when the program returned with the terminal still
# there, so the user ended it. After a hangup the record stays for the next
# shell in this tab or split.
clear_record() {
  need_surface
  have_terminal || return 0
  rm -f -- "$record" || fail "cannot remove $record"
}

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  C_B=$'\033[1m' C_DIM=$'\033[2m' C_ATTN=$'\033[33m' C_KEY=$'\033[1;34m' C_OFF=$'\033[0m'
else
  C_B='' C_DIM='' C_ATTN='' C_KEY='' C_OFF=''
fi

# Silent unless this surface holds a record of a cut-off program, and then
# only on a terminal: off-tty there is nobody to ask.
restore() {
  [[ "$surface" =~ $uuid_re && -f "$record" ]] || exit 0
  local name=''
  IFS= read -r name <"$record" || [[ -n "$name" ]] || exit 0
  if ! program "$name"; then
    rm -f -- "$record"
    exit 0
  fi
  [[ -t 0 && -t 2 ]] || exit 0

  gate() {
    printf '\n%snext: start %s again in this tab or split;%s %sEnter%s starts it%s · %sn%s%s skips%s\n' \
      "$C_B" "$label" "$C_OFF" "$C_KEY" "$C_OFF" "$C_DIM" "$C_KEY" "$C_OFF" "$C_DIM" "$C_OFF" >&2
  }

  gate
  local answer rc
  while :; do
    if ! IFS= read -r answer; then
      answer=n                                  # end of input declines
    fi
    case "$answer" in
      ''|y|yes)
        # The record stays while the program runs, so a second Ghostty quit
        # offers it again; a return with the terminal still there clears it.
        rc=0
        "$path" || rc=$?
        have_terminal && rm -f -- "$record"
        exit "$rc"
        ;;
      n|no)
        rm -f -- "$record"
        printf '%sskipped; %s will not be offered again in this tab or split%s\n' \
          "$C_ATTN" "$label" "$C_OFF" >&2
        exit 0
        ;;
      *)
        printf '%snot an answer; Enter or y starts %s, n skips%s\n' "$C_ATTN" "$label" "$C_OFF" >&2
        gate
        ;;
    esac
  done
}

case "${1:-}" in
  note)
    [[ $# -eq 2 ]] || { usage >&2; exit 1; }
    note "$2"
    ;;
  clear)
    [[ $# -eq 1 ]] || { usage >&2; exit 1; }
    clear_record
    ;;
  --restore)
    [[ $# -eq 1 ]] || { usage >&2; exit 1; }
    restore
    ;;
  -h|--help) usage ;;
  *) usage >&2; exit 1 ;;
esac
