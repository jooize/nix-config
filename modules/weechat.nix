{ pkgs, ... }:
{
  # WeeChat as a SYSTEM package -> /run/current-system/sw/bin, like gh in
  # git.nix: root-owned, pinned to flake.lock. Its config and logs stay in
  # the XDG folders WeeChat picks by default (~/.config/weechat and
  # ~/.local/share/weechat).
  environment.systemPackages = [ pkgs.weechat ];
}
