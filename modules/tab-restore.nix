{ lib, pkgs, ... }:
let
  # A store path, root-owned: the shell startup calls it by this path, never
  # through PATH. `a` at the restore prompt re-runs it under sudo (approve),
  # so sudo shows this same path.
  tabRestore = pkgs.writeShellApplication {
    name = "tab-restore";
    text = lib.removePrefix "#!/usr/bin/env bash\n"
      (builtins.readFile ./tab-restore/tab-restore.bash);
  };
  bin = "${tabRestore}/bin/tab-restore";

  # A command is noted only when it is made of plain words (tab-restore's
  # word_re, joined by spaces), so it means the same thing when it runs again.
  # Checked in the shell first, so other commands cost no extra process.
  word = "[A-Za-z0-9_./=:,@+%-]+";
  lineRe = "^${word}( +${word})*$";
in
{
  options.tabRestore = {
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
    # `tab-restore` on PATH starts the noted command by hand and lists or
    # changes the approvals (root-owned, /var/db/tab-restore/approved).
    environment.systemPackages = [ tabRestore ];

    # Note each command while it runs in a Ghostty tab or split, so the next
    # shell there can start it again when a Ghostty quit or a restart cut it
    # off. A command that returns with the terminal still there clears it.
    tabRestore.fishInit = ''
      if status is-interactive; and set -q GHOSTTY_SURFACE_ID
          function __tab_restore_note --on-event fish_preexec
              set -l line (string trim -- $argv[1])
              if string match -qr -- '${lineRe}' "$line"
                  set -g __tab_restore_noted
                  ${bin} note (string split -n ' ' -- $line)
              end
          end
          function __tab_restore_clear --on-event fish_postexec
              if set -q __tab_restore_noted
                  set -e __tab_restore_noted
                  ${bin} clear
              end
          end
          ${bin} --restore
      end
    '';
    tabRestore.zshInit = ''
      if [[ -n $GHOSTTY_SURFACE_ID ]]; then
        autoload -Uz add-zsh-hook
        _tab_restore_note() {
          # Spaces only around and between the words, so splitting on IFS
          # below yields exactly those words.
          if [[ $1 =~ '^ *${word}( +${word})* *$' ]]; then
            typeset -g _tab_restore_noted=1
            ${bin} note ''${=1}
          fi
        }
        _tab_restore_clear() {
          [[ -n ''${_tab_restore_noted-} ]] || return 0
          unset _tab_restore_noted
          ${bin} clear
        }
        add-zsh-hook preexec _tab_restore_note
        add-zsh-hook precmd _tab_restore_clear
        ${bin} --restore
      fi
    '';
  };
}
