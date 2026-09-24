{ pkgs, ... }:
{
  # nix-darwin needs the home dir to locate HM's target.
  users.users.jooize.home = "/Users/jooize";

  # gh as a SYSTEM package -> /run/current-system/sw/bin: root-owned, on PATH,
  # pinned to flake.lock, gcroot-protected. Not user-writable, so no
  # write-to-execute surface (the whole point vs a ~/.nix-profile bin).
  environment.systemPackages = [ pkgs.gh ];

  # git itself comes from claude-hardening's git-trust module (the shim first
  # on PATH, /etc/git/config, /etc/git/ignore, gitleaks). home-manager no
  # longer manages git; this deploy lets it remove the ~/.config/git links it
  # made. Nothing else uses home-manager, so it can be dropped afterwards.
  home-manager.users.jooize = {
    home.stateVersion = "26.05";  # VERIFY: match your nixpkgs release
  };
}
