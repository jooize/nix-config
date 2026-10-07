{ lib, pkgs, ... }:
let
  # WeeChat built without its fifo plugin. The fifo is a named pipe through
  # which any process running as the user can type commands into a running
  # WeeChat (post as the user, or send decrypted /secure values over IRC).
  # A setting (fifo.file.enabled) lives in WeeChat's own config, which the
  # same processes can switch back; a plugin that was never built cannot be
  # loaded. Costs a source build after each nixpkgs update.
  #
  # Not covered: WeeChat's config and script folders stay writable by the
  # user, so anything running as the user can still change what WeeChat does
  # the next time it starts.
  weechat = pkgs.wrapWeechat (pkgs.weechat-unwrapped.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ [ (lib.cmakeBool "ENABLE_FIFO" false) ];
  })) { };
in
{
  # WeeChat as a SYSTEM package -> /run/current-system/sw/bin, like gh in
  # git.nix: root-owned, pinned to flake.lock. Its config and logs stay in
  # the XDG folders WeeChat picks by default (~/.config/weechat and
  # ~/.local/share/weechat).
  environment.systemPackages = [ weechat ];
}
