{ ... }:
let
  user = "jooize";
in
{
  # The system configuration file of our patched Ghostty (jooize/Ghostty,
  # branch hardening, patch system-config). It is read before anything else
  # and only if every path component is root-owned and not writable by group
  # or others; the store symlink chain passes. Vanilla Ghostty never reads
  # this path, so the file is inert until the patched build is installed.
  #
  # The whole configuration lives here: user files and command-line config
  # are switched off, so a launch environment that points Ghostty elsewhere
  # (XDG_CONFIG_HOME, HOME, CFFIXED_USER_HOME, GHOSTTY_CONFIG_PATH, --args)
  # finds nothing to load. Colors are inline rather than `theme = Ayu`,
  # because a theme is a config file found by name.
  #
  # Single-user: `command` names this user's fish shim.
  environment.etc."ghostty/config.ghostty".text = ''
    config-default-files = false
    config-cli-args = false

    # Nix installs and updates the app; the bundle is root-owned.
    auto-update = off

    # direct: runs fish under login(1) without bash, so BASH_ENV is never read.
    command = direct:/etc/profiles/per-user/${user}/bin/fish --login --interactive

    font-family = "JetBrains Mono"
    font-size = 18
    macos-option-as-alt = left
    window-save-state = always

    # Ayu, from Ghostty 1.3.1's bundled theme.
    palette = 0=#11151c
    palette = 1=#ea6c73
    palette = 2=#7fd962
    palette = 3=#f9af4f
    palette = 4=#53bdfa
    palette = 5=#cda1fa
    palette = 6=#90e1c6
    palette = 7=#c7c7c7
    palette = 8=#686868
    palette = 9=#f07178
    palette = 10=#aad94c
    palette = 11=#ffb454
    palette = 12=#59c2ff
    palette = 13=#d2a6ff
    palette = 14=#95e6cb
    palette = 15=#ffffff
    background = #0b0e14
    foreground = #bfbdb6
    cursor-color = #e6b450
    cursor-text = #0b0e14
    selection-background = #409fff
    selection-foreground = #0b0e14
  '';
}
