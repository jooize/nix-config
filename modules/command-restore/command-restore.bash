#!/usr/bin/env bash
# command-restore: start a command again in the Ghostty tab or split where a
# Ghostty quit or a restart cut it off.
#
# Usage:
#   command-restore                    start the command noted for this tab or split
#   command-restore --restore          at shell start: start an approved command,
#                                  ask about any other
#   command-restore note <word>...     note the command that starts now (shell hook)
#   command-restore clear              forget it: the command returned (shell hook)
#   command-restore approved           list the approved commands, both lists
#   sudo command-restore approve <word>...  approve a command to start on its own
#   sudo command-restore revoke <word>...   take an approval back
#
# The root-owned shell startup (fish init, /etc/zdotdir/.zshrc) calls `note`
# before every command made only of plain words, and `clear` once it returns.
# `clear` keeps the note when the terminal is gone (see have_terminal), so a
# note survives only when a Ghostty quit or a restart cut the command off.
#
# One note per surface, keyed by GHOSTTY_SURFACE_ID (Ghostty patch
# surface-id; Ghostty saves the id with the window state):
#   $XDG_STATE_HOME/command-restore/<SURFACE_ID>   line 1 the folder, line 2 the words
#
# Notes are user-writable, so they are data: every word must be a plain word
# (letters, digits, - _ . / = : , @ + %), nothing passes through a shell, and
# the program is looked up on PATH again at start. A plain word means the same
# thing to the shell that ran it and to us, so the line shown is the line that
# runs. A command the shell would have expanded (quotes, $, ~, globs, ;, |) is
# never noted.
#
# Approvals are root-owned, because a list the user can write would approve
# anything for any process running as the user. Two lists, one line of words
# each, and a line in either one counts:
#   /var/db/command-restore/approved  written by `sudo command-restore approve`
#   /etc/command-restore/approved     declared: nix-config installs it from
#                                     modules/command-restore/approved
# Both use the same format, so moving the runtime list into Nix is a plain
# copy of the file. An approved command starts on its own, but only
# when its program resolves to a root-owned path; every other command asks,
# and Enter declines: a command cut off midway may be one that must not run
# twice.

set -uo pipefail

usage() {
  cat <<'EOF'
Usage:
  command-restore                    start the command noted for this tab or split
  command-restore --restore          at shell start: start an approved command,
                                 ask about any other
  command-restore note <word>...     note the command that starts now (shell hook)
  command-restore clear              forget it: the command returned (shell hook)
  command-restore approved           list the approved commands, both lists
  sudo command-restore approve <word>...  approve a command to start on its own
  sudo command-restore revoke <word>...   take an approval back
EOF
}

uuid_re='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
word_re='^[A-Za-z0-9_./=:,@+%-]+$'
approved_dir=/var/db/command-restore
approved_file=$approved_dir/approved
declared_file=/etc/command-restore/approved

# Commands with a restore of their own, or that would restart this one.
skip_names=(claude claude-continue command-restore)

surface=${GHOSTTY_SURFACE_ID:-}
dir="${XDG_STATE_HOME:-$HOME/.local/state}/command-restore"
record="$dir/$surface"

fail() {
  printf 'command-restore: %s\n' "$1" >&2
  exit 1
}

need_surface() {
  [[ -n "$surface" ]] || fail "not in a Ghostty tab or split (GHOSTTY_SURFACE_ID is unset)"
  [[ "$surface" =~ $uuid_re ]] || fail "GHOSTTY_SURFACE_ID is not a UUID"
}

# All words plain, the first not an option.
plain_words() {
  (( $# > 0 )) || return 1
  [[ "$1" != -* ]] || return 1
  local w
  for w in "$@"; do
    [[ "$w" =~ $word_re ]] || return 1
  done
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

# Every component of the path, and of what it resolves to, is root-owned and
# writable by nobody this user can act as: not by others, and not by a group
# the user is in. (/nix/store is group-writable by the Nix build group, which
# the user is not in, and sticky.) So no process running as the user could
# have put the program there.
root_owned_path() {
  local p=$1 real node c owner group mode g
  local -a parts groups
  real=$(/bin/realpath -- "$p" 2>/dev/null) || return 1
  read -r -a groups < <(/usr/bin/id -G)
  for p in "$p" "$real"; do
    node=''
    IFS=/ read -r -a parts <<<"${p#/}"
    for c in "${parts[@]}"; do
      node="$node/$c"
      [[ -L "$node" ]] && continue          # the target is checked via $real
      read -r owner group mode < <(/usr/bin/stat -f '%u %g %Lp' -- "$node" 2>/dev/null) || return 1
      [[ "$owner" == 0 ]] || return 1
      (( (8#$mode & 8#002) == 0 )) || return 1
      if (( (8#$mode & 8#020) != 0 )); then
        for g in "${groups[@]}"; do [[ "$g" == "$group" ]] && return 1; done
      fi
    done
  done
}

# Read the note into cwd and words. Fails on anything that is not a valid note.
read_note() {
  [[ -f "$record" ]] || return 1
  local line2=''
  { IFS= read -r cwd && IFS= read -r line2; } <"$record" || [[ -n "$line2" ]] || return 1
  [[ "$cwd" == /* && -d "$cwd" ]] || return 1
  read -r -a words <<<"$line2"
  plain_words "${words[@]}"
}

# Whether a list holds this exact line.
in_list() {
  [[ -f "$1" ]] && grep -qxF -- "$2" "$1"
}

is_approved() {
  in_list "$approved_file" "${words[*]}" || in_list "$declared_file" "${words[*]}"
}

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  C_B=$'\033[1m' C_DIM=$'\033[2m' C_ATTN=$'\033[33m' C_KEY=$'\033[1;34m'
  C_ROOT=$'\033[1;36m' C_OFF=$'\033[0m'
else
  C_B='' C_DIM='' C_ATTN='' C_KEY='' C_ROOT='' C_OFF=''
fi

# The lines that run, drawn the terminal-output way: the program's first path
# segment bold cyan, its name and every token starting with - bold blue.
# Control characters are stripped from the folder; the words are plain.
show_command() {
  local shown_cwd first rest base w line
  shown_cwd=$(LC_ALL=C tr -d '[:cntrl:]' <<<"$cwd")
  printf '  %scd%s %s\n' "$C_KEY" "$C_OFF" "$shown_cwd" >&2
  first=${path#/}; first=${first%%/*}
  rest=${path#/"$first"}; base=${rest##*/}; rest=${rest%/*}
  line="  ${C_ROOT}/${first}${C_OFF}${rest}/${C_KEY}${base}${C_OFF}"
  for w in "${words[@]:1}"; do
    if [[ "$w" == -* ]]; then line+=" ${C_KEY}${w}${C_OFF}"; else line+=" $w"; fi
  done
  printf '%s\n' "$line" >&2
}

# Start the noted command. The note stays while it runs, so another Ghostty
# quit offers it again; a return with the terminal still there clears it.
start() {
  local rc=0
  cd -- "$cwd" || fail "cannot enter $cwd"
  "$path" "${words[@]:1}" || rc=$?
  have_terminal && rm -f -- "$record"
  exit "$rc"
}

# --- subcommands -------------------------------------------------------------

note() {
  need_surface
  plain_words "$@" || fail "not plain words: the command is not noted"
  local name=${1##*/} s
  for s in "${skip_names[@]}"; do [[ "$name" == "$s" ]] && return 0; done
  type -P -- "$1" >/dev/null || return 0     # a function or builtin: nothing to start
  [[ "$PWD" == /* ]] || fail "the current folder is unknown"
  mkdir -p -- "$dir" || fail "cannot create $dir"
  local tmp
  tmp=$(mktemp "$dir/.$surface.XXXXXX") || fail "cannot write in $dir"
  if printf '%s\n%s\n' "$PWD" "$*" >"$tmp" && mv -f -- "$tmp" "$record"; then
    return 0
  fi
  rm -f -- "$tmp"
  fail "cannot write $record"
}

clear_record() {
  need_surface
  have_terminal || return 0
  rm -f -- "$record" || fail "cannot remove $record"
}

# Root side of `a`: sudo shows the command line before it authenticates.
approve() {
  (( EUID == 0 )) || fail "approve writes a root-owned list: run it with sudo"
  plain_words "$@" || fail "not plain words: nothing approved"
  local line="$*" tmp
  if in_list "$approved_file" "$line" || in_list "$declared_file" "$line"; then
    printf '%salready approved:%s %s\n' "$C_DIM" "$C_OFF" "$line" >&2
    return 0
  fi
  [[ -d "$approved_dir" ]] || mkdir -m 755 -- "$approved_dir" || fail "cannot create $approved_dir"
  tmp=$(mktemp "$approved_dir/.approved.XXXXXX") || fail "cannot write in $approved_dir"
  if { [[ -f "$approved_file" ]] && cat -- "$approved_file"; printf '%s\n' "$line"; } >"$tmp" \
     && chmod 644 -- "$tmp" && mv -f -- "$tmp" "$approved_file"; then
    printf '✓ approved: %s\n' "$line" >&2
    return 0
  fi
  rm -f -- "$tmp"
  fail "cannot write $approved_file"
}

revoke() {
  (( EUID == 0 )) || fail "revoke writes a root-owned list: run it with sudo"
  plain_words "$@" || fail "not plain words"
  local line="$*" tmp
  if ! in_list "$approved_file" "$line"; then
    in_list "$declared_file" "$line" \
      && fail "declared in $declared_file: remove it from nix-config, then deploy"
    fail "not approved: $line"
  fi
  tmp=$(mktemp "$approved_dir/.approved.XXXXXX") || fail "cannot write in $approved_dir"
  if { grep -vxF -- "$line" "$approved_file" || true; } >"$tmp" \
     && chmod 644 -- "$tmp" && mv -f -- "$tmp" "$approved_file"; then
    printf '✓ revoked: %s\n' "$line" >&2
    in_list "$declared_file" "$line" \
      && printf '%sstill approved: %s declares it%s\n' "$C_ATTN" "$declared_file" "$C_OFF" >&2
    return 0
  fi
  rm -f -- "$tmp"
  fail "cannot write $approved_file"
}

# Each list under its path, the lines on stdout and the labels on stderr, so
# `command-restore approved >file` keeps only the lines.
list_approved() {
  local f
  for f in "$approved_file" "$declared_file"; do
    printf '%s%s%s\n' "$C_DIM" "$f" "$C_OFF" >&2
    if [[ -s "$f" ]]; then
      cat -- "$f"
    else
      printf '%snothing approved%s\n' "$C_DIM" "$C_OFF" >&2
    fi
  done
}

# Manual start: the human asked, so no prompt.
start_by_hand() {
  need_surface
  read_note || fail "no command noted for this tab or split"
  path=$(type -P -- "${words[0]}") || fail "${words[0]} is not on PATH"
  show_command
  start
}

# Shell start: silent unless this surface holds a note of a cut-off command.
restore() {
  [[ "$surface" =~ $uuid_re && -f "$record" ]] || exit 0
  if ! read_note; then
    rm -f -- "$record"
    printf '%scommand-restore: dropped an unreadable note (%s)%s\n' \
      "$C_DIM" "$record" "$C_OFF" >&2
    exit 0
  fi
  [[ -t 0 && -t 2 ]] || exit 0              # off-tty there is nobody to ask
  path=$(type -P -- "${words[0]}") || exit 0
  local name=${words[0]##*/}

  if is_approved && root_owned_path "$path"; then
    printf '%s%s was running in this tab when Ghostty closed. Starting %s.%s\n\n' \
      "$C_DIM" "$name" "$name" "$C_OFF" >&2
    show_command
    printf '\n' >&2
    start
  fi

  printf '%s%s was running in this tab when Ghostty closed.%s\n\n' "$C_DIM" "$name" "$C_OFF" >&2
  show_command
  local gate
  printf -v gate '%srun the lines above? [%sy%s%s/%sN%s%s]%s%s · %sl%s%s ask later · %sa%s%s always%s ' \
    "$C_B" "$C_KEY" "$C_OFF" "$C_B" "$C_KEY" "$C_OFF" "$C_B" "$C_OFF" \
    "$C_DIM" "$C_KEY" "$C_OFF" "$C_DIM" "$C_KEY" "$C_OFF" "$C_DIM" "$C_OFF"
  printf '\n%s' "$gate" >&2
  local answer
  while :; do
    if ! IFS= read -r answer; then
      # End of input is no answer: a Ghostty quit or a restart while the
      # gate waits hangs up the terminal, and the read can return before the
      # hangup signal ends this process. Keep the note, like l, so the next
      # shell in this tab asks again.
      printf '\n' >&2    # the cursor waits on the gate line
      answer=l
    fi
    case "$answer" in
      y|yes) start ;;
      ''|n|no)
        rm -f -- "$record"
        printf '%saborted; %s not started%s\n' "$C_ATTN" "$name" "$C_OFF" >&2
        exit 2
        ;;
      l)
        printf '%skept; the next shell in this tab asks again%s\n' "$C_DIM" "$C_OFF" >&2
        exit 0
        ;;
      a)
        if sudo -- "$0" approve "${words[@]}"; then
          start
        fi
        # Back to the same gate, printed again so the answer has its keys.
        printf '%snot approved; the lines above did not run%s\n%s' "$C_ATTN" "$C_OFF" "$gate" >&2
        ;;
      *)
        # The gate line follows again, without its blank line, so the next
        # answer is typed beside its keys.
        printf '%snot an answer%s\n%s' "$C_ATTN" "$C_OFF" "$gate" >&2
        ;;
    esac
  done
}

case "${1:-}" in
  '') start_by_hand ;;
  --restore) [[ $# -eq 1 ]] || { usage >&2; exit 1; }; restore ;;
  note) shift; note "$@" ;;
  clear) [[ $# -eq 1 ]] || { usage >&2; exit 1; }; clear_record ;;
  approve) shift; approve "$@" ;;
  revoke) shift; revoke "$@" ;;
  approved) list_approved ;;
  -h|--help) usage ;;
  *) usage >&2; exit 1 ;;
esac
