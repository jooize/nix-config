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

  # Build sandbox on (2026-09-08). A non-fixed-output build gets no network
  # and no filesystem reach beyond its declared inputs; fixed-output
  # derivations (fetchers) keep network by design. The daemon is not a
  # security boundary against untrusted users (Lix manual), so this only
  # narrows what a build you DO run can touch. sandbox-fallback stays off
  # so a package that cannot build sandboxed fails loudly instead of quietly
  # building without one. claude-update's builds were checked: its fetches
  # are fixed-output, its gpgv step needs no network, nothing runs codesign.
  nix.settings.sandbox = true;
  nix.settings.sandbox-fallback = false;

  # Flakes-only: no nix-channel command or state. This also removes two
  # user-writable references from generated root-owned output (verified
  # upstream, modules/nix/default.nix): the set-environment guard that
  # prepends ~/.nix-defexpr/channels to NIX_PATH whenever that dir exists,
  # and the on-login initialization that would recreate ~/.nix-defexpr
  # after the 2026-08-05 home-entry purge.
  nix.channel.enable = false;
}
