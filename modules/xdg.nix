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

  # The one zsh user rc, declarative at $ZDOTDIR/.zshrc (read-only store
  # symlink). zsh's compdump already defaults to $ZDOTDIR/.zcompdump, so only
  # history needs pointing at XDG state. The state dir is created by the
  # migration script (zsh does not mkdir HISTFILE parents).
  home-manager.users.jooize = {
    xdg.configFile."zsh/.zshrc".text = ''
      HISTFILE="$HOME/.local/state/zsh/history"
      HISTSIZE=10000
      SAVEHIST=10000
    '';
  };
}
