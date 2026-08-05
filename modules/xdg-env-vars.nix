# Single source of truth for the XDG relocation env vars. Pure data, imported
# by BOTH consumers so they cannot drift:
#   - xdg.nix      -> environment.variables (set-environment: /etc/zshenv,
#                     /etc/bashrc) + launchd.user.envVariables (GUI apps)
#   - fish.nix     -> rendered into the root-owned fish init (the shim skips
#                     set-environment by design, so parity lives there)
#
# Values are $HOME-relative so the machine-global shell surface stays
# MULTIUSER-correct: set-environment exports these inside double quotes and
# nix-darwin itself relies on that expansion ($USER in PATH, $HOME in the
# channels guard -- verified in the deployed store file), and fish expands
# $HOME inside double quotes the same way. Values reference $HOME only, never
# each other: set-environment emits exports in attrset order, so a var
# referencing a sibling could read it before it is set.
#
# The one surface that cannot expand -- launchd.user.envVariables -- gets a
# literal per-user substitution at its call site in xdg.nix, because that
# surface is per-user by nature (launchctl setenv in the user's context).
let
  config = "$HOME/.config";
  data = "$HOME/.local/share";
  state = "$HOME/.local/state";
  cache = "$HOME/.cache";
in
{
  XDG_CONFIG_HOME = config;
  XDG_DATA_HOME = data;
  XDG_STATE_HOME = state;
  XDG_CACHE_HOME = cache;

  # Tool homes relocated out of ~ (2026-08-05 home-entry audit, hardening
  # .agents-work/20260805-interactive-trust-chain/AUDIT-home-entries.md).
  CARGO_HOME = "${data}/cargo";
  GOPATH = "${data}/go";
  COLIMA_HOME = "${data}/colima";
  TART_HOME = "${data}/tart";
  DOCKER_CONFIG = "${config}/docker";
  NPM_CONFIG_CACHE = "${cache}/npm";

  # zsh reads $ZDOTDIR/.z* instead of ~/.z* -- set in root-owned /etc/zshenv
  # (and the fish init for fish-spawned zsh), so attacker-created ~/.zshrc
  # et al. are dead code. The rc itself is HM-managed (xdg.nix).
  ZDOTDIR = "${config}/zsh";

  # Apple Terminal per-shell session restore (~/.zsh_sessions,
  # ~/.bash_sessions) -- useless under Ghostty.
  SHELL_SESSIONS_DISABLE = "1";
}
