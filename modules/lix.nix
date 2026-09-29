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
  # Patched (2026-09-30): macOS 27 refuses to load Lix's build sandbox
  # profile, so every sandboxed build failed with "invalid errno value #45".
  # The one rule using an errno clause, a file-write-mode deny on the build
  # directory, is removed; the owner/flags/xattr/mount denies stay. Cost: a
  # build can now change its own build directory's mode, e.g. open it to
  # other local users while it runs, which a hostile build can already
  # approximate through the shared /tmp. Unfixed upstream as of Lix 2.95.3
  # and main. `patches` fails the build loudly if a Lix update moves or
  # rewrites the rule: then check upstream and drop this override.
  nix.package = pkgs.lix.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./lix/sandbox-no-enotsup.patch ];
  });
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
