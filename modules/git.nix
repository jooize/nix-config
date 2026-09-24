{ pkgs, ... }:
{
  # gh as a SYSTEM package -> /run/current-system/sw/bin: root-owned, on PATH,
  # pinned to flake.lock, gcroot-protected. Not user-writable, so no
  # write-to-execute surface (the whole point vs a ~/.nix-profile bin).
  environment.systemPackages = [ pkgs.gh ];

  # git itself comes from claude-hardening's git-trust module (the shim first
  # on PATH, /etc/git/config, /etc/git/ignore, gitleaks).
}
