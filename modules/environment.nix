{ lib, ... }:
{
  # The intended nix-darwin knob for the PATH (and NIX_PROFILES, XDG_*_DIRS,
  # TERMINFO_DIRS) that set-environment bakes into root-owned /etc/zshenv and
  # /etc/bashrc: environment.profiles. The default merges $HOME/.nix-profile
  # in FRONT (mkOrder 800, ahead of the per-user profile at 900) -- nix's
  # user-imperative profile, populatable via the nix daemon WITHOUT root, so
  # the conventional order hands every shell an interposition slot ahead of
  # all root-owned bins. Force the root-owned tail only: zsh/bash entry
  # points (SSH, Terminal.app -- the escape-hatch login shell stays /bin/zsh)
  # get the same PATH discipline the fish init constructs for itself.
  # ~/.nix-profile is a dangling symlink on this machine; nothing is lost.
  environment.profiles = lib.mkForce [
    "/etc/profiles/per-user/$USER"
    "/run/current-system/sw"
    "/nix/var/nix/profiles/default"
  ];
}
