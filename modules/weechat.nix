{ pkgs, ... }:
{
  # WeeChat as a SYSTEM package -> /run/current-system/sw/bin, like gh in
  # git.nix: root-owned, pinned to flake.lock. Its config and logs stay in
  # the XDG folders WeeChat picks by default (~/.config/weechat and
  # ~/.local/share/weechat).
  environment.systemPackages = [ pkgs.weechat ];

  # A Ghostty quit or a restart cuts WeeChat off; the next shell in that tab
  # offers to start it again (tab-restore.nix). Quitting it yourself does not.
  tabRestore.programs.weechat = {
    label = "WeeChat";
    path = "${pkgs.weechat}/bin/weechat";
  };
}
