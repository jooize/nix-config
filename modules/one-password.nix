{ pkgs, ... }:
let
  user = "jooize";
in
{
  # 1Password CLI (`op`). Lands in the root-owned per-user profile
  # (/etc/profiles/per-user/${user}/bin), the same surface as the fish shim --
  # nothing user-writable on PATH. Desktop-app integration (Settings >
  # Developer > "Integrate with 1Password CLI") authorizes op per client
  # binary, so expect a one-time re-approval prompt after version bumps
  # (the store path changes). Unfree: admitted by name in flake.nix's
  # allowUnfreePredicate.
  users.users.${user}.packages = [ pkgs._1password-cli ];
}
