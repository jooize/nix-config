#!/usr/bin/env bash
# command-restore: start a command again in the Ghostty tab or split where a
# Ghostty quit or a restart cut it off.
#
# Usage:
#   command-restore                    start the command noted for this tab or split
#   command-restore --restore          at shell start: start an approved command,
#                                      ask about any other
#   command-restore line               print the noted line and forget it, for
#                                      the shell to put on its command line (e)
#   command-restore note <line>        note the command line that starts now (shell hook)
#   command-restore clear              forget it: the command returned (shell hook)
#   command-restore list               list your approved commands, both lists
#   sudo command-restore approve <folder> <command> [<arg>...]
#                                      approve a command in a folder to start on its own
#   sudo command-restore revoke <folder> <command> [<arg>...]
#                                      take an approval back
#
# The root-owned shell startup (fish init, /etc/zdotdir/.zshrc) calls `note`
# with the line of every one-line command made only of plain words (and of
# every `claude` line, see the Claude rule), and `clear` once it returns.
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
# anything for any process running as the user. Each user has two lists, and
# a line in either one counts. A line is the folder, a tab, then the words:
# an approval covers the folder and the command together, so a note (or a
# window state that opens a shell elsewhere) cannot pick another folder for
# an approved command. The folder may hold any character
# but a control character (tab and newline included).
#   /var/db/command-restore/approved/<user>  written by `sudo command-restore approve`
#   /etc/command-restore/approved/<user>     declared: nix-config installs it from
#                                            modules/command-restore/approved/<user>
# Both use the same format, so moving the runtime list into Nix is a plain
# copy of the file. An approved command starts on its own, but only
# when its program resolves to a root-owned path; every other command asks,
# and Enter declines: a command cut off midway may be one that must not run
# twice. At the prompt, e puts the line on the shell's command line instead,
# unrun, to change before Enter: the shell startup calls `line` when
# --restore exits 3 (fish commandline -r, zsh print -z).
#
# Nothing here changes folder. Ghostty restores each surface's folder (the
# last one its shell reported), and a command starts only when the shell
# starts in the folder it was noted in; elsewhere this says where it ran and
# stops. The shell keeps its folder, so Cmd+T copies the right one and the
# shell is still there when the command returns.
#
# Claude Code (claude): a restored `claude` resumes the session this surface
# held rather than starting a new one. The session comes from the record
# claude-hardening's surface-session hook keeps per surface,
#   $XDG_STATE_HOME/agents/claude/surfaces/<SURFACE_ID>.json
# read as data: the id must be a UUID, the session must have run in this
# folder, and its conversation file must exist (Claude writes it at the first
# message; a session without one has nothing to resume). The noted words lose
# their own session flags (-c, --continue, -r/--resume and the id or name
# after it, --session-id and its id, --fork-session); an approval covers what
# is left, and the line that runs adds --resume <id>. `claude --model haiku`
# comes back as `claude --model haiku --resume <id>`, approved as
# `claude --model haiku`.
# The note already leaves out -r/--resume/--session-id and their argument,
# quoted or not, so `claude --resume "fable designs"` is noted as `claude`.
# A prompt stays on the line (telling one from an option's value needs
# claude's option table), so `claude hello` comes back sending hello again;
# the line shown before it starts says so when that is sure.

set -uo pipefail

usage() {
  cat <<'EOF'
Usage:
  command-restore                    start the command noted for this tab or split
  command-restore --restore          at shell start: start an approved command,
                                     ask about any other
  command-restore line               print the noted line and forget it, for
                                     the shell to put on its command line (e)
  command-restore note <line>        note the command line that starts now (shell hook)
  command-restore clear              forget it: the command returned (shell hook)
  command-restore list               list your approved commands, both lists
  sudo command-restore approve <folder> <command> [<arg>...]
                                     approve a command in a folder to start on its own
  sudo command-restore revoke <folder> <command> [<arg>...]
                                     take an approval back
EOF
}

uuid_re='^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'
word_re='^[A-Za-z0-9_./=:,@+%-]+$'
# One of claude's session flags and its argument, between spaces: a plain
# word, a single-quoted string, or a double-quoted one with no $, ` or \ (one
# with any of those is left, so the line is not noted).
session_arg_re=" (-r|--resume|--session-id)(( +|=)('[^']*'|\"[^\"\$\`\\\\]*\"|[^ '\"-][^ ]*))? "
approved_dir=/var/db/command-restore/approved
declared_dir=/etc/command-restore/approved

# Commands that would restart this one.
skip_names=(command-restore)

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

# Point approved_file and declared_file at one user's lists: the account
# running this, or under sudo the account that ran sudo (sudo sets SUDO_USER
# itself, so the caller cannot choose it).
lists_for() {
  [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || fail "not a user name: $1"
  approved_file=$approved_dir/$1
  declared_file=$declared_dir/$1
}

# The user that ran sudo, for the root-side subcommands.
sudo_user() {
  (( EUID == 0 )) || fail "$1 writes a root-owned list: run it with sudo"
  [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != root ]] \
    || fail "$1 names the user by sudo: run sudo command-restore $1 from that account"
  lists_for "$SUDO_USER"
}

# Whether a list holds this exact line.
in_list() {
  [[ -f "$1" ]] && grep -qxF -- "$2" "$1"
}

# Build the approval line for a folder and words into `line`: the folder, a
# tab, the words. Fails on a relative folder, a control character in it, or
# words that are not plain.
approval_line() {
  local LC_ALL=C folder=$1; shift
  [[ "$folder" == /* && ! "$folder" =~ [[:cntrl:]] ]] || return 1
  plain_words "$@" || return 1
  line="$folder"$'\t'"$*"
}

# An approval line as a person reads it: the words, then the folder.
shown() {
  printf '%s  %sin%s %s' "${1#*$'\t'}" "$C_DIM" "$C_OFF" "${1%%$'\t'*}"
}

is_approved() {
  local line
  approval_line "$cwd" "${approve_words[@]}" || return 1
  in_list "$approved_file" "$line" || in_list "$declared_file" "$line"
}

# A folder as prose: ~ for home, control characters removed.
tilde() {
  local f=$1
  [[ "$f" == "$HOME" || "$f" == "$HOME"/* ]] && f="~${f#"$HOME"}"
  LC_ALL=C tr -d '[:cntrl:]' <<<"$f"
}

# Whether the shell is in the noted folder. Physical paths, so a symlinked
# spelling of the same folder matches.
in_noted_folder() {
  local there
  here=$(pwd -P) || return 1
  there=$(cd -P -- "$cwd" 2>/dev/null && pwd -P) || return 1
  [[ "$here" == "$there" ]]
}

# The Claude rule (header): fill approve_words and run_words for a noted
# `claude`, from this surface's session record. Fails when there is no
# session here to resume.
claude_words() {
  local rec sid transcript ran w drop=0
  rec="${XDG_STATE_HOME:-$HOME/.local/state}/agents/claude/surfaces/$surface.json"
  [[ -f "$rec" ]] || return 1
  # Unit separator between fields; the folder last, so it reads whole.
  IFS=$'\x1f' read -r -d '' sid transcript ran < <(jq -j \
    '[.session_id // "", .transcript // "", .cwd // ""] | join("\u001f")' "$rec" 2>/dev/null) || true
  [[ "$sid" =~ $uuid_re ]] || return 1
  [[ "$transcript" == /* && "${transcript##*/}" == "$sid.jsonl" && -f "$transcript" ]] || return 1
  [[ "$(cd -P -- "$ran" 2>/dev/null && pwd -P)" == "$here" ]] || return 1
  approve_words=("${words[0]}")
  for w in "${words[@]:1}"; do
    if (( drop )); then
      drop=0
      [[ "$w" != -* ]] && continue           # the id or name that flag named
    fi
    case "$w" in
      -c|--continue|--fork-session|--resume=*|--session-id=*) continue ;;
      -r|--resume|--session-id) drop=1; continue ;;
    esac
    approve_words+=("$w")
  done
  run_words=("${approve_words[@]}" --resume "$sid")
}

# The word a restored claude line sends again as its prompt, into
# prompt_word, or empty. Claude sends its first positional word as the prompt
# and ignores any after it (measured, 2.1.296), but which words are positional
# depends on which options take a value. Two cases are sure without that
# table: a plain word right after `claude`, `--` or an option written with =,
# none of which takes the next word; and a plain word right after another
# plain word, since an option takes one value. A plain word after a bare
# option (`--model haiku`, `--verbose hi`) is not flagged. An option with
# several values (--add-dir a b) and a subcommand (`claude doctor`) are
# flagged although no prompt is sent.
claude_prompt_word() {
  local w free=1
  prompt_word=''
  for w in "${approve_words[@]:1}"; do
    if [[ "$w" != -* ]]; then
      (( free )) && { prompt_word=$w; return 0; }
      free=1
    elif [[ "$w" == -- || "$w" == -*=* ]]; then
      free=1
    else
      free=0
    fi
  done
}

# Resolve the program and fill approve_words and run_words: the noted words,
# or for claude the Claude rule. Fails with `why` set.
prepare() {
  path=$(type -P -- "${words[0]}") || { why="not on PATH: ${words[0]}"; return 1; }
  if [[ "${words[0]##*/}" == claude ]]; then
    claude_words || { why="no Claude session with messages to resume here"; return 1; }
  else
    approve_words=("${words[@]}")
    run_words=("${words[@]}")
  fi
}

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  C_B=$'\033[1m' C_DIM=$'\033[2m' C_ATTN=$'\033[33m' C_KEY=$'\033[1;34m'
  C_ROOT=$'\033[1;36m' C_OK=$'\033[32m' C_OFF=$'\033[0m'
else
  C_B='' C_DIM='' C_ATTN='' C_KEY='' C_ROOT='' C_OK='' C_OFF=''
fi

# The line that runs, drawn the terminal-output way: the program's first path
# segment bold cyan, its name and every token starting with - bold blue. The
# words are plain; it runs in this folder, so there is no cd line.
show_command() {
  local first rest base w line
  first=${path#/}; first=${first%%/*}
  rest=${path#/"$first"}; base=${rest##*/}; rest=${rest%/*}
  line="  ${C_ROOT}/${first}${C_OFF}${rest}/${C_KEY}${base}${C_OFF}"
  for w in "${run_words[@]:1}"; do
    if [[ "$w" == -* ]]; then line+=" ${C_KEY}${w}${C_OFF}"; else line+=" $w"; fi
  done
  printf '%s\n' "$line" >&2
  if [[ "${words[0]##*/}" == claude ]]; then
    claude_prompt_word
    [[ -z "$prompt_word" ]] \
      || printf '  %ssends this prompt to the session again: %s%s\n' "$C_ATTN" "$prompt_word" "$C_OFF" >&2
  fi
}

# Tell Ghostty which folder this surface is in (OSC 7, the shape Ghostty's
# own shell integration sends: file://<host><path>, the path URL-escaped).
# The integration first reports at the first prompt, and a command started at
# shell start runs before any prompt; without this Ghostty saves no folder for
# the surface, and the next restore opens it in the default folder, where the
# note no longer starts.
report_folder() {
  local LC_ALL=C s=$PWD out='' c i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case "$c" in
      [A-Za-z0-9/._~-]) out+=$c ;;
      *) printf -v c '%%%02X' "'$c"; out+=$c ;;
    esac
  done
  printf '\033]7;file://%s%s\a' "${HOSTNAME:-}" "$out" >&2
}

# Start the noted command, here. The note stays while it runs, so another
# Ghostty quit offers it again; a return with the terminal still there clears
# it. By hand the command's exit status is ours; at shell start it is 0, so
# the startup reads only this tool's own codes (2 declined, 3 edit).
start() {
  local rc=0
  [[ "${1:-}" == restore ]] && report_folder
  "$path" "${run_words[@]:1}" || rc=$?
  have_terminal && rm -f -- "$record"
  [[ "${1:-}" == restore ]] && exit 0
  exit "$rc"
}

# --- subcommands -------------------------------------------------------------

# A line that is not one line of plain words is simply not noted: the shell
# hooks send every `claude` line, quoted prompts included.
note() {
  need_surface
  (( $# == 1 )) || fail "note takes the command line as one argument"
  local line=$1 name s
  [[ "$line" != *$'\n'* ]] || return 0
  read -r -a words <<<"$line"
  if [[ "${words[0]:-}" == claude || "${words[0]:-}" == */claude ]]; then
    line=" $line "
    while [[ "$line" =~ $session_arg_re ]]; do
      line=${line/"${BASH_REMATCH[0]}"/ }
    done
    read -r -a words <<<"$line"
  fi
  plain_words "${words[@]}" || return 0
  name=${words[0]##*/}
  for s in "${skip_names[@]}"; do [[ "$name" == "$s" ]] && return 0; done
  type -P -- "${words[0]}" >/dev/null || return 0   # a function or builtin: nothing to start
  [[ "$PWD" == /* ]] || fail "the current folder is unknown"
  mkdir -p -- "$dir" || fail "cannot create $dir"
  local tmp
  tmp=$(mktemp "$dir/.$surface.XXXXXX") || fail "cannot write in $dir"
  if printf '%s\n%s\n' "$PWD" "${words[*]}" >"$tmp" && mv -f -- "$tmp" "$record"; then
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
  sudo_user approve
  local line tmp
  approval_line "$@" || fail "needs an absolute folder, then plain words: nothing approved"
  if in_list "$approved_file" "$line" || in_list "$declared_file" "$line"; then
    printf '%salready approved:%s %s\n' "$C_DIM" "$C_OFF" "$(shown "$line")" >&2
    return 0
  fi
  # One level at a time, so each folder gets 755 whatever umask sudo passed on.
  local d
  for d in "${approved_dir%/*}" "$approved_dir"; do
    [[ -d "$d" ]] || mkdir -m 755 -- "$d" || fail "cannot create $d"
  done
  tmp=$(mktemp "$approved_dir/.${approved_file##*/}.XXXXXX") || fail "cannot write in $approved_dir"
  # chmod without --: macOS chmod stops reading options at the mode, so a --
  # after it is a file name. $tmp is absolute, so it never reads as an option.
  if { [[ -f "$approved_file" ]] && cat -- "$approved_file"; printf '%s\n' "$line"; } >"$tmp" \
     && chmod 644 "$tmp" && mv -f -- "$tmp" "$approved_file"; then
    printf '%s✓%s approved: %s\n' "$C_OK" "$C_OFF" "$(shown "$line")" >&2
    return 0
  fi
  rm -f -- "$tmp"
  fail "cannot write $approved_file"
}

revoke() {
  sudo_user revoke
  local line tmp
  approval_line "$@" || fail "needs an absolute folder, then plain words"
  if ! in_list "$approved_file" "$line"; then
    in_list "$declared_file" "$line" \
      && fail "declared in $declared_file: remove it from nix-config, then deploy"
    fail "not approved: $(shown "$line")"
  fi
  tmp=$(mktemp "$approved_dir/.${approved_file##*/}.XXXXXX") || fail "cannot write in $approved_dir"
  if { grep -vxF -- "$line" "$approved_file" || true; } >"$tmp" \
     && chmod 644 "$tmp" && mv -f -- "$tmp" "$approved_file"; then
    printf '%s✓%s revoked: %s\n' "$C_OK" "$C_OFF" "$(shown "$line")" >&2
    in_list "$declared_file" "$line" \
      && printf '%sstill approved: %s declares it%s\n' "$C_ATTN" "$declared_file" "$C_OFF" >&2
    return 0
  fi
  rm -f -- "$tmp"
  fail "cannot write $approved_file"
}

# Each list under its path, one approval per line as a person reads it. The
# files themselves are the format to copy; this is only the view.
list_approved() {
  local f line n
  [[ -t 1 ]] || local C_DIM='' C_ATTN='' C_OFF=''
  for f in "$approved_file" "$declared_file"; do
    printf '%s%s%s\n' "$C_DIM" "$f" "$C_OFF"
    n=0
    if [[ -f "$f" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -n "$line" ]] || continue
        n=$((n + 1))
        if [[ "$line" == *$'\t'* ]]; then
          printf '  %s\n' "$(shown "$line")"
        else
          printf '  %s  %s(no folder: never matches)%s\n' \
            "$(LC_ALL=C tr -d '[:cntrl:]' <<<"$line")" "$C_ATTN" "$C_OFF"
        fi
      done <"$f"
    fi
    (( n > 0 )) || printf '  %snothing approved%s\n' "$C_DIM" "$C_OFF"
  done
}

# Manual start: the human asked, so no prompt.
start_by_hand() {
  need_surface
  read_note || fail "no command noted for this tab or split"
  in_noted_folder || fail "it ran in $(tilde "$cwd"): cd there, then run command-restore"
  prepare || fail "$why"
  show_command
  start
}

# For e: the line the prompt showed, as words the shell reads back unchanged
# (plain words and a UUID), for the shell to put on its command line. The
# note goes: the line is the user's now, and running it notes it again.
line_for_shell() {
  need_surface
  read_note || fail "no command noted for this tab or split"
  in_noted_folder || fail "it ran in $(tilde "$cwd")"
  prepare || fail "$why"
  rm -f -- "$record"
  printf '%s\n' "${run_words[*]}"
}

# The rows a restore screen shows under its first sentence: a folder or a
# name is a value whose length this program does not choose, so each ends a
# labeled row of its own and no sentence or question holds one.
row() { # <label> <value>
  printf '%s%-9s%s %s\n' "$C_B" "$1:" "$C_OFF" "$2" >&2
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
  local name=${words[0]##*/}

  # Elsewhere: say where it ran and keep the note.
  if ! in_noted_folder; then
    printf '%sThis tab was running a command when Ghostty closed.%s\n' "$C_DIM" "$C_OFF" >&2
    row command "$name"
    row 'ran in' "$(tilde "$cwd")"
    row here "$(tilde "$(pwd)")"
    printf '%sIt starts only in the folder it ran in. To start it there:%s\n\n' "$C_DIM" "$C_OFF" >&2
    printf '  %scd%s %s\n  %scommand-restore%s\n\n' "$C_KEY" "$C_OFF" \
      "$(LC_ALL=C tr -d '[:cntrl:]' <<<"$cwd")" "$C_KEY" "$C_OFF" >&2
    exit 0
  fi
  if ! prepare; then
    rm -f -- "$record"
    printf '%sThis tab was running a command when Ghostty closed. It does not start:%s\n' \
      "$C_DIM" "$C_OFF" >&2
    row command "$name"
    row reason "$why"
    exit 0
  fi

  if is_approved && root_owned_path "$path"; then
    printf '%sThis tab was running a command when Ghostty closed. Starting it again.%s\n' \
      "$C_DIM" "$C_OFF" >&2
    row folder "$(tilde "$cwd")"
    printf '\n' >&2
    show_command
    printf '\n' >&2
    start restore
  fi

  # The question names the command line with a noun ("the line above") and
  # holds no value: the folder it runs in, which an approval would cover,
  # is the row above the command line.
  printf '%sThis tab was running a command when Ghostty closed.%s\n' "$C_DIM" "$C_OFF" >&2
  row folder "$(tilde "$cwd")"
  printf '\n' >&2
  show_command
  local gate
  printf -v gate '%srun the line above? [%sy%s%s/%sN%s%s]%s%s · %se%s%s edit · %sa%s%s always%s ' \
    "$C_B" "$C_KEY" "$C_OFF" "$C_B" "$C_KEY" "$C_OFF" "$C_B" "$C_OFF" \
    "$C_DIM" "$C_KEY" "$C_OFF" "$C_DIM" "$C_KEY" "$C_OFF" "$C_DIM" "$C_OFF"
  printf '\n%s' "$gate" >&2
  local answer
  while :; do
    if ! IFS= read -r answer; then
      # End of input is no answer: a Ghostty quit or a restart while the
      # gate waits hangs up the terminal, and the read can return before the
      # hangup signal ends this process. Keep the note, so the next shell in
      # this tab asks again.
      printf '\n%skept; the next shell in this tab asks again%s\n' "$C_DIM" "$C_OFF" >&2
      exit 0
    fi
    case "$answer" in
      y|yes) start restore ;;
      e)
        # The startup puts the line on the command line (`line`); the note
        # stays until then.
        printf '%son the command line; Enter runs it%s\n' "$C_DIM" "$C_OFF" >&2
        exit 3
        ;;
      ''|n|no)
        rm -f -- "$record"
        printf '%saborted; the command did not start%s\n' "$C_ATTN" "$C_OFF" >&2
        exit 2
        ;;
      a)
        # sudo shows only the store path and its arguments, so say first
        # what the approval does and where it goes.
        local line
        approval_line "$cwd" "${approve_words[@]}" || fail "the note is not an approvable line"
        # The session flags are not in the approval (the Claude rule), so
        # say where the session comes from instead.
        local resumes=''
        [[ "$name" == claude ]] && resumes=", resuming the tab's own session"
        printf 'An approval starts this command in this folder without asking after a\n' >&2
        printf 'Ghostty quit%s. sudo asks next, then adds it to the list.\n' "$resumes" >&2
        row command "${line#*$'\t'}"
        row folder "${line%%$'\t'*}"
        row list "$approved_file"
        if sudo -- "$0" approve "$cwd" "${approve_words[@]}"; then
          start restore
        fi
        # Back to the same gate, under the command line again, so "the line
        # above" names it and the answer has its keys.
        printf '%snot approved; the command did not start%s\n\n' "$C_ATTN" "$C_OFF" >&2
        show_command
        printf '\n%s' "$gate" >&2
        ;;
      *)
        # The gate line follows again, without its blank line, so the next
        # answer is typed beside its keys.
        printf '%snot an answer%s\n%s' "$C_ATTN" "$C_OFF" "$gate" >&2
        ;;
    esac
  done
}

me=$(/usr/bin/id -un) || fail "cannot tell which user this is"
lists_for "$me"

case "${1:-}" in
  '') start_by_hand ;;
  --restore) [[ $# -eq 1 ]] || { usage >&2; exit 1; }; restore ;;
  line) [[ $# -eq 1 ]] || { usage >&2; exit 1; }; line_for_shell ;;
  note) shift; note "$@" ;;
  clear) [[ $# -eq 1 ]] || { usage >&2; exit 1; }; clear_record ;;
  approve) shift; approve "$@" ;;
  revoke) shift; revoke "$@" ;;
  list) list_approved ;;
  -h|--help) usage ;;
  *) usage >&2; exit 1 ;;
esac
