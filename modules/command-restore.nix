{ lib, pkgs, ... }:
let
  # A store path, root-owned: the shell startup calls it by this path, never
  # through PATH. `a` at the restore prompt re-runs it under sudo (approve),
  # so sudo shows this same path.
  commandRestore = pkgs.writeShellApplication {
    name = "command-restore";
    text = lib.removePrefix "#!/usr/bin/env bash\n"
      (builtins.readFile ./command-restore/command-restore.bash);
  };
  bin = "${commandRestore}/bin/command-restore";

  # A command is noted only when it is made of plain words (command-restore's
  # word_re, joined by spaces), so it means the same thing when it runs again.
  # Checked in the shell first, so other commands cost no extra process.
  word = "[A-Za-z0-9_./=:,@+%-]+";
  lineRe = "^${word}( +${word})*$";
in
{
  options.commandRestore = {
    fishInit = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      description = "fish init lines: the note hooks and the restore prompt.";
    };
    zshInit = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      description = "/etc/zdotdir/.zshrc lines: the note hooks and the restore prompt.";
    };
  };

  config = {
    # `command-restore` on PATH starts the noted command by hand and lists or
    # changes the approvals (root-owned, /var/db/command-restore/approved).
    environment.systemPackages = [ commandRestore ];

    # Declared approvals, read beside the runtime list. Same format, so
    # bootstrapping is `cp /var/db/command-restore/approved` to this folder.
    # Absent file, no /etc entry.
    environment.etc = lib.optionalAttrs (builtins.pathExists ./command-restore/approved) {
      "command-restore/approved".source = ./command-restore/approved;
    };

    # Note each command while it runs in a Ghostty tab or split, so the next
    # shell there can start it again when a Ghostty quit or a restart cut it
    # off. A command that returns with the terminal still there clears it.
    commandRestore.fishInit = ''
      if status is-interactive; and set -q GHOSTTY_SURFACE_ID
          function __command_restore_note --on-event fish_preexec
              set -l line (string trim -- $argv[1])
              if string match -qr -- '${lineRe}' "$line"
                  set -g __command_restore_noted
                  ${bin} note (string split -n ' ' -- $line)
              end
          end
          function __command_restore_clear --on-event fish_postexec
              if set -q __command_restore_noted
                  set -e __command_restore_noted
                  ${bin} clear
              end
          end
          ${bin} --restore
      end
    '';
    commandRestore.zshInit = ''
      if [[ -n $GHOSTTY_SURFACE_ID ]]; then
        autoload -Uz add-zsh-hook
        _command_restore_note() {
          # Spaces only around and between the words, so splitting on IFS
          # below yields exactly those words.
          if [[ $1 =~ '^ *${word}( +${word})* *$' ]]; then
            typeset -g _command_restore_noted=1
            ${bin} note ''${=1}
          fi
        }
        _command_restore_clear() {
          [[ -n ''${_command_restore_noted-} ]] || return 0
          unset _command_restore_noted
          ${bin} clear
        }
        add-zsh-hook preexec _command_restore_note
        add-zsh-hook precmd _command_restore_clear
        ${bin} --restore
      fi
    '';
  };
}
