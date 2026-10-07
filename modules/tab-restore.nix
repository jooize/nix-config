{ config, lib, pkgs, ... }:
let
  cfg = config.tabRestore;
  names = lib.attrNames cfg.programs;

  # One case arm per listed program. Names are checked below to be plain
  # words, so they are safe as case patterns and in the shell hooks.
  arms = lib.concatStrings (lib.mapAttrsToList (n: p: ''
    ${n}) label=${lib.escapeShellArg p.label} path=${lib.escapeShellArg p.path} ;;
  '') cfg.programs);

  # A store path, root-owned: the shell startup calls it by this path, never
  # through PATH.
  tabRestore = pkgs.writeShellApplication {
    name = "tab-restore";
    text = lib.replaceStrings [ "@PROGRAMS@" ] [ arms ]
      (lib.removePrefix "#!/usr/bin/env bash\n"
        (builtins.readFile ./tab-restore/tab-restore.bash));
  };
  bin = "${tabRestore}/bin/tab-restore";
in
{
  options.tabRestore = {
    programs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          label = lib.mkOption {
            type = lib.types.str;
            description = "Name shown in the prompt, e.g. WeeChat.";
          };
          path = lib.mkOption {
            type = lib.types.str;
            description = "Store path of the program to start, without arguments.";
          };
        };
      });
      default = { };
      description = ''
        Programs a Ghostty tab or split starts again after a Ghostty quit or a
        restart cut them off. The attribute name is the command's first word.
      '';
    };
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
    assertions = [{
      assertion = lib.all (n: builtins.match "[a-z0-9][a-z0-9_-]*" n != null) names;
      message = "tabRestore.programs: names must be plain lowercase words";
    }] ++ lib.mapAttrsToList (n: p: {
      assertion = lib.hasPrefix "/nix/store/" p.path;
      message = "tabRestore.programs.${n}.path must be a store path";
    }) cfg.programs;

    # Note a listed program while it runs in a Ghostty tab or split, so the
    # next shell there can offer it again when a Ghostty quit or a restart
    # cut it off. Quitting the program yourself clears the note.
    tabRestore.fishInit = lib.optionalString (names != [ ]) ''
      if status is-interactive; and set -q GHOSTTY_SURFACE_ID
          function __tab_restore_note --on-event fish_preexec
              set -l word (string split -n -f1 -- ' ' (string trim -- $argv[1]))
              if contains -- "$word" ${lib.concatStringsSep " " names}
                  set -g __tab_restore_noted
                  ${bin} note $word
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
    tabRestore.zshInit = lib.optionalString (names != [ ]) ''
      if [[ -n $GHOSTTY_SURFACE_ID ]]; then
        autoload -Uz add-zsh-hook
        _tab_restore_note() {
          local word=''${''${(z)1}[1]}
          case $word in
            (${lib.concatStringsSep "|" names})
              typeset -g _tab_restore_noted=1
              ${bin} note $word
              ;;
          esac
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
