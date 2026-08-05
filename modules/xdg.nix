{ ... }:
let
  vars = import ./xdg-env-vars.nix;
in
{
  # zsh/bash entry points: set-environment baked into root-owned /etc/zshenv
  # and /etc/bashrc. ZDOTDIR lands in /etc/zshenv, which zsh reads BEFORE any
  # user file, so the ~/.z* lookup never happens again.
  environment.variables = vars;

  # GUI-launched processes (launchctl setenv at activation) -- so apps like
  # Hammerspoon see the same XDG world as the shells.
  launchd.user.envVariables = vars;

  # The one zsh user rc, declarative at $ZDOTDIR/.zshrc (read-only store
  # symlink). zsh's compdump already defaults to $ZDOTDIR/.zcompdump, so only
  # history needs pointing at XDG state. The state dir is created by the
  # migration script (zsh does not mkdir HISTFILE parents).
  home-manager.users.jooize = {
    xdg.configFile."zsh/.zshrc".text = ''
      HISTFILE=/Users/jooize/.local/state/zsh/history
      HISTSIZE=10000
      SAVEHIST=10000
    '';
  };
}
