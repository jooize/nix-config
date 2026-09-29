{ ... }:
let
  user = "jooize";
in
{
  # The system configuration file of our patched Ghostty (jooize/Ghostty,
  # branch hardening, patches system-config and protected-config). It is
  # read before anything else and only if every path component is
  # root-owned and not writable by group or others; the store symlink chain
  # passes. Vanilla Ghostty never reads this path, so the file is inert
  # until the patched build is installed.
  #
  # Only what must hold for every window lives here. Fonts and colors live
  # in ~/.config/ghostty/config.ghostty, sealed by `locked`, so they change
  # without a deploy. `config-file-protection = required` loads that file,
  # and every other file a configuration names, only if no process running
  # as the user could have changed it; locations come from the user
  # database, never from HOME, XDG_CONFIG_HOME or CFFIXED_USER_HOME. A file
  # that fails is skipped and named in the config-errors window.
  # Command-line config stays off, so an instance started with --args finds
  # nothing to load.
  #
  # Single-user: `command` names this user's fish shim.
  environment.etc."ghostty/config.ghostty".text = ''
    config-file-protection = required
    config-cli-args = false

    # Nix installs and updates the app; the bundle is root-owned.
    auto-update = off

    # direct: runs fish under login(1) without bash, so BASH_ENV is never read.
    command = direct:/etc/profiles/per-user/${user}/bin/fish --login --interactive
  '';
}
