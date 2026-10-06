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
  users.users.jooize.home = "/Users/jooize";

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
  #
  # The same file drops the names in bash-startup-vars.nix, so no bash started
  # below this shell obeys them. zsh itself already drops BASH_FUNC_* entries
  # (not valid names to it), so only the plain names need unsetting.
  programs.zsh.shellInit = ''
    export ZDOTDIR=/etc/zdotdir
    unset ${lib.concatStringsSep " " (import ./bash-startup-vars.nix).names}
  '';
  environment.etc."zdotdir/.zshrc".text = ''
    HISTFILE="$HOME/.local/state/zsh/history"
    HISTSIZE=10000
    SAVEHIST=10000

    # Completions from root-owned dirs only (the profiles' site-functions, then
    # zsh's own). -D: no dump file. compinit sources its dump, and the default
    # one ($ZDOTDIR/.zcompdump, or anywhere under $HOME) would be a file any
    # process as the user could write. Costs about 0.3 s per shell start.
    fpath=(/etc/profiles/per-user/jooize/share/zsh/site-functions /run/current-system/sw/share/zsh/site-functions $fpath)
    autoload -Uz compinit && compinit -D

    # direnv: an .envrc loads only when pinned approved it (claude-hardening's
    # direnv-trust module); replaces `direnv hook zsh`.
    ${config.direnvTrust.zshInit}

    # Offer to resume the Claude session this Ghostty surface held when a
    # Ghostty quit or a restart cut it off. claude-continue (claude-hardening)
    # reads its per-surface record as data and asks before anything runs.
    if [[ -n $GHOSTTY_SURFACE_ID && -x /etc/profiles/per-user/jooize/bin/claude-continue ]]; then
      /etc/profiles/per-user/jooize/bin/claude-continue --restore
    fi
  '';
}
