# nix-darwin module: Lix as the Nix package.
#
# Separate module (rather than bundled with claude-code.nix) because the
# Nix-flavor choice is orthogonal to Claude Code hardening — anything else
# that needs Nix relies on it too.
#
# Rationale:
#   - nix-darwin's own README recommends the Lix installer by default
#     (uninstaller, macOS upgrade survival, faster Linux sandbox launch).
#   - Determinate Systems' installer stopped defaulting to upstream Nix on
#     2025-11-10 and now ships only Determinate Nix as of 2026-01-01.
#   - Lix is on a steady ~6-month cadence with active community governance.
#   - Full compatibility with existing flakes; no technical regression.
#
# Rollback: change to `pkgs.nix` and darwin-rebuild switch.

{ pkgs, ... }:

{
  nix.package = pkgs.lix;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Flakes-only: no nix-channel command or state. This also removes two
  # user-writable references from generated root-owned output (verified
  # upstream, modules/nix/default.nix): the set-environment guard that
  # prepends ~/.nix-defexpr/channels to NIX_PATH whenever that dir exists,
  # and the on-login initialization that would recreate ~/.nix-defexpr
  # after the 2026-08-05 home-entry purge.
  nix.channel.enable = false;
}
