{ lib, pkgs, ... }:
let
  # The first of nvim, vim, vi on PATH, looked up each time it runs, so
  # installing or removing nvim needs no change here. PATH is the caller's:
  # the root-owned profile dirs in the shells, secure_path under sudo.
  editor = pkgs.writeShellScript "editor" ''
    for e in nvim vim vi; do
      if command -v "$e" >/dev/null 2>&1; then exec "$e" "$@"; fi
    done
    echo "editor: none of nvim, vim, vi is on PATH" >&2
    exit 127
  '';
in
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

  # The editor every shell exports: set-environment carries it into zsh and
  # bash, and fish.nix renders these same values. Tools that open an editor
  # read them -- locked edit (SUDO_EDITOR, then VISUAL, then EDITOR, as sudo
  # passes them through) and git (core.editor is pinned to
  # ${VISUAL:-${EDITOR:-vi}}). A store path, so finding the wrapper itself
  # never depends on PATH.
  environment.variables = {
    EDITOR = "${editor}";
    VISUAL = "${editor}";
  };
}
