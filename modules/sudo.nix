{ ... }:
{
  # sudo runs commands with the CALLER's PATH by default: probed live
  # 2026-08-06, `sudo printenv PATH` returned the user's full PATH (macOS
  # sets no secure_path; sudoers env_reset keeps PATH). Today every entry
  # is root-owned, but that is convention and session state -- nix
  # develop / direnv shells hand a project-authored PATH to root the
  # moment sudo is typed inside one, and any root script resolving tools
  # by bare name inherits it. secure_path makes root's PATH a constant.
  #
  # The per-user profile is included on purpose: it is ROOT-OWNED
  # (home-manager useUserPackages), so `sudo <hm-tool>` keeps working
  # without weakening anything. /usr/local/bin is deliberately absent
  # (the classic chown-to-user target); absolute paths still work.
  #
  # nix-darwin's terminfo module contributes to the same extraConfig
  # (types.lines concatenates); both land in
  # /etc/sudoers.d/10-nix-darwin-extra-config.
  security.sudo.extraConfig = ''
    Defaults secure_path="/etc/profiles/per-user/jooize/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  '';
}
