{ lib, config, ... }:
let
  vars = import ./xdg-env-vars.nix;
  # launchctl setenv does no shell expansion, so this per-user surface binds
  # $HOME to the primary user here. Additional users would need their own
  # binding -- the shared data stays $HOME-relative and multiuser-correct.
  home = config.users.users.jooize.home;
  literal = lib.mapAttrs (_: v: lib.replaceStrings [ "$HOME" ] [ home ] v) vars;
in
{
  # zsh/bash entry points: set-environment baked into root-owned /etc/zshenv
  # and /etc/bashrc; $HOME expands per-user at source time. ZDOTDIR lands in
  # /etc/zshenv, which zsh reads BEFORE any user file, so the ~/.z* lookup
  # never happens again.
  environment.variables = vars;

  # GUI-launched processes (launchctl setenv in the user's context) -- so
  # apps like Hammerspoon see the same XDG world as the shells.
  launchd.user.envVariables = literal;

  # zsh startup is root-owned end to end. ZDOTDIR is exported here
  # UNCONDITIONALLY from /etc/zshenv (programs.zsh.shellInit renders outside
  # the __NIX_DARWIN_SET_ENVIRONMENT_DONE guard), because the guarded
  # set-environment path can be skipped by anything that pre-sets the guard
  # variable and ZDOTDIR in the inherited environment -- `launchctl setenv`
  # from any process running as the user reaches every GUI-launched shell.
  # zsh reads /etc/zshenv before any user file and only `-f` skips it. The
  # directory itself is /etc/zdotdir (root-owned via environment.etc), not
  # ~/.config/zsh: a store symlink inside a user-owned directory can be
  # replaced by the same user process. zsh's compdump would default to
  # $ZDOTDIR/.zcompdump, which is unwritable there; the rc never runs
  # compinit, so nothing tries.
  programs.zsh.shellInit = ''
    export ZDOTDIR=/etc/zdotdir
  '';
  environment.etc."zdotdir/.zshrc".text = ''
    HISTFILE="$HOME/.local/state/zsh/history"
    HISTSIZE=10000
    SAVEHIST=10000
  '';
}
