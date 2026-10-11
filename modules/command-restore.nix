{ lib, pkgs, ... }:
let
  commandRestore = pkgs.writeShellApplication {
    name = "command-restore";
    # jq reads claude-hardening's per-surface session record (the Claude rule).
    runtimeInputs = [ pkgs.jq ];
    text = lib.removePrefix "#!/usr/bin/env bash\n"
      (builtins.readFile ./command-restore/command-restore.bash);
  };
  # The shell startup calls it by this path, never through PATH: root-owned
  # at every step (the system profile, then the store), and each deploy
  # points it at the new build, so a shell started before a deploy runs the
  # current one. `a` at the restore prompt re-runs it under sudo (approve),
  # so sudo shows this same path. systemPackages below puts it there.
  bin = "/run/current-system/sw/bin/command-restore";

  # A command is noted only when it is made of plain words (command-restore's
  # word_re, joined by spaces), so it means the same thing when it runs again.
  # Checked in the shell first, so other commands cost no extra process.
  word = "[A-Za-z0-9_./=:,@+%-]+";
  lineRe = "^${word}( +${word})*$";
  # A claude line goes to `note` whole, quotes and all: note drops its
  # session flags and their argument (`--resume "fable designs"`) and then
  # applies the same plain-word rule.
  claudeRe = "^([^ ]*/)?claude( |$)";
in
{
  options.commandRestore = {
    fishInit = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      description = "fish init lines: the note hooks, the restore prompt and its e.";
    };
    zshInit = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      description = "/etc/zdotdir/.zshrc lines: the note hooks, the restore prompt and its e.";
    };
  };

  config = {
    # `command-restore` on PATH starts the noted command by hand and lists or
    # changes your approvals (root-owned, /var/db/command-restore/approved/<user>).
    environment.systemPackages = [ commandRestore ];

    # Declared approvals, one file per user, read beside that user's runtime
    # list. Same format, so bootstrapping is
    # `cp /var/db/command-restore/approved/<user> command-restore/approved/`.
    # No folder or no file, no /etc entry.
    environment.etc = lib.mapAttrs'
      (user: _: lib.nameValuePair "command-restore/approved/${user}" {
        source = ./command-restore/approved + "/${user}";
      })
      (lib.filterAttrs (_: type: type == "regular")
        (lib.optionalAttrs (builtins.pathExists ./command-restore/approved)
          (builtins.readDir ./command-restore/approved)));

    # Note each command while it runs in a Ghostty tab or split, so the next
    # shell there can start it again when a Ghostty quit or a restart cut it
    # off. A command that returns with the terminal still there clears it.
    commandRestore.fishInit = ''
      if status is-interactive; and set -q GHOSTTY_SURFACE_ID
          # One line only (collect keeps a multi-line buffer whole, so the
          # match refuses it), and only a program from PATH: a builtin or a
          # function (cd, a wrapper) would come back as some other program of
          # that name.
          function __command_restore_note --on-event fish_preexec
              set -l line (string trim -- $argv[1] | string collect)
              if string match -qr -- '${lineRe}' "$line"; or string match -qr -- '${claudeRe}' "$line"
                  and test "$(type -t -- (string split -f1 ' ' -- $line) 2>/dev/null)" = file
                  set -g __command_restore_noted
                  ${bin} note "$line"
              end
          end
          function __command_restore_clear --on-event fish_postexec
              if set -q __command_restore_noted
                  set -e __command_restore_noted
                  ${bin} clear
              end
          end
          # 3: the user chose e; the line goes on the command line, unrun.
          ${bin} --restore
          if test $status -eq 3; and set -g __command_restore_line (${bin} line)
              function __command_restore_prefill --on-event fish_prompt
                  functions -e __command_restore_prefill
                  commandline -r -- $__command_restore_line
                  set -e __command_restore_line
              end
          end
      end
    '';
    commandRestore.zshInit = ''
      if [[ -n $GHOSTTY_SURFACE_ID ]]; then
        autoload -Uz add-zsh-hook
        zmodload zsh/parameter
        _command_restore_note() {
          # Spaces only around and between the words, so splitting on IFS
          # below yields exactly those words; the match refuses a multi-line
          # buffer. Only a program from PATH: an alias, function, builtin or
          # reserved word (cd, a wrapper) would come back as some other
          # program of that name.
          [[ $1 =~ '^ *${word}( +${word})* *$' || $1 =~ '^ *([^ ]*/)?claude( |$)' ]] || return 0
          local -a w=(''${=1})
          (( ''${+aliases[$w[1]]} || ''${+functions[$w[1]]} \
             || ''${+builtins[$w[1]]} || ''${+reswords[$w[1]]} )) && return 0
          typeset -g _command_restore_noted=1
          ${bin} note "$1"
        }
        _command_restore_clear() {
          [[ -n ''${_command_restore_noted-} ]] || return 0
          unset _command_restore_noted
          ${bin} clear
        }
        add-zsh-hook preexec _command_restore_note
        add-zsh-hook precmd _command_restore_clear
        # 3: the user chose e; the line goes on the command line, unrun.
        ${bin} --restore
        if (( $? == 3 )); then
          _command_restore_line=$(${bin} line) && print -rz -- "$_command_restore_line"
          unset _command_restore_line
        fi
      fi
    '';
  };
}
