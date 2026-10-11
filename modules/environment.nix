{ lib, ... }:
{
  # The intended nix-darwin knob for the PATH (and NIX_PROFILES, XDG_*_DIRS,
  # TERMINFO_DIRS) that set-environment bakes into root-owned /etc/zshenv and
  # /etc/bashrc: environment.profiles. The default merges $HOME/.nix-profile
  # in FRONT (mkOrder 800, ahead of the per-user profile at 900) -- nix's
  # user-imperative profile, populatable via the nix daemon WITHOUT root, so
  # the conventional order hands every shell an interposition slot ahead of
  # all root-owned bins. Force the root-owned tail only: zsh/bash entry
  # points (SSH, Terminal.app -- the escape-hatch login shell stays /bin/zsh)
  # get the same PATH discipline the fish init constructs for itself.
  # ~/.nix-profile is a dangling symlink on this machine; nothing is lost.
  environment.profiles = lib.mkForce [
    "/etc/profiles/per-user/$USER"
    "/run/current-system/sw"
    "/nix/var/nix/profiles/default"
  ];

  # The editor every shell exports: the first of nvim, vim, vi on the PATH
  # set just above (root-owned profile dirs only), as a full path, looked up
  # at shell start, so installing nvim needs no change here and a new shell
  # picks it up. Tools name the editor by that path's file name (Claude
  # Code's ctrl+g shows `vim`). Unset when none is found: nix-darwin exports
  # EDITOR=nano by default (no option removes it), and an inherited value
  # must not survive either. fish.nix does the same lookup. Tools that open
  # an editor read these -- locked edit (SUDO_EDITOR, then VISUAL, then
  # EDITOR, as sudo passes them through) and git (core.editor is pinned to
  # ${VISUAL:-${EDITOR:-vi}}).
  environment.extraInit = ''
    unset EDITOR VISUAL
    for __editor in nvim vim vi; do
      __editor=$(command -v "$__editor") || continue
      case $__editor in
        /*) export EDITOR="$__editor" VISUAL="$__editor"; break ;;
      esac
    done
    unset __editor
  '';
}
