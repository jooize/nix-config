{ lib, pkgs, ... }:
let
  user = "jooize";

  # The release this Mac runs, from jooize/Ghostty's releases. Before
  # pinning a new one, check that CI built it from the commit you reviewed,
  # and that both hashes agree with the release's SHA256SUMS:
  #
  #   gh attestation verify Ghostty.app.zip -R jooize/Ghostty \
  #     --signer-workflow jooize/Ghostty/.github/workflows/build.yml \
  #     --source-ref refs/tags/v<version> --source-digest <commit> \
  #     --deny-self-hosted-runners
  #
  # Releases after 1.3.1+hardening.1 attest manifest.txt too; check it the
  # same way.
  release = {
    version = "1.3.1+hardening.2";
    zipHash = "sha256-8eZOZTwGA00dDTlCFXPHFmfoX1tNxULFdAGdbG7y2GA=";
    manifestHash = "sha256-QijVknRcYWd7MyaSUHqGOLaE1wnqBF/MJ+i7nClKHI8=";
  };
  releaseFile = name: hash: pkgs.fetchurl {
    url = "https://github.com/jooize/Ghostty/releases/download/v${lib.escapeURL release.version}/${name}";
    inherit hash;
  };

  app = pkgs.callPackage ./ghostty/app.nix {
    inherit (release) version;
    zip = releaseFile "Ghostty.app.zip" release.zipHash;
    manifest = releaseFile "manifest.txt" release.manifestHash;
  };
  swap = pkgs.writeCBin "ghostty-swap" (builtins.readFile ./ghostty/swap.c);
in
{
  assertions = [{
    assertion = lib.all (lib.hasPrefix "sha256-") [ release.zipHash release.manifestHash ];
    message = "modules/ghostty.nix: the Ghostty release ${release.version} is not pinned yet";
  }];

  # Install the app at /Applications/Ghostty.app: a real directory, owned by
  # root, never a link into the store. The fish init sources shell
  # integration from that fixed path only if every component is root-owned
  # and none is a link, and Launch Services and privacy permissions (TCC)
  # expect an app there. Not via environment.systemPackages, which would
  # also copy it into /Applications/Nix Apps.
  #
  # /Applications is writable by the admin group, so any process running as
  # the user can rename the bundle away and put something else there; that
  # replacement cannot be root-owned (the fish init refuses it) and the next
  # deploy puts the app back. Inside the bundle nothing is writable but by
  # root.
  #
  # The new bundle is copied into a root-only folder on the same volume,
  # verified there, and exchanged with whatever is at the target in one
  # rename (ghostty/swap.c). What it replaced is kept until the next
  # install, since a running Ghostty still loads files from its own bundle.
  # The marker records the store path and the identity (owner, volume,
  # inode) of the bundle installed; a deploy with the same app and the same
  # bundle in place does nothing.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo "setting up /Applications/Ghostty.app..." >&2
    (
      set -euo pipefail
      target=/Applications/Ghostty.app
      state=/var/db/ghostty
      marker=$state/installed
      staging=$state/staging
      staged=$staging/Ghostty.app
      wanted=${app}/Applications/Ghostty.app

      fail() {
        printf >&2 '\e[1;31merror: Ghostty install: %s\e[0m\n' "$1"
        exit 1
      }
      # Owner, volume and inode; without -L a link reports itself. BSD stat
      # by absolute path: activation puts GNU coreutils first on PATH.
      identity() { /usr/bin/stat -f '%u %d:%i' "$1"; }

      /bin/mkdir -p "$state"
      /usr/sbin/chown root:wheel "$state"
      /bin/chmod 700 "$state"

      if [[ -f $marker && ! -L $target && -d $target ]] &&
        [[ "$(<"$marker")" == "$wanted $(identity "$target")" ]]; then
        exit 0
      fi

      /bin/rm -rf "$staging"
      /bin/mkdir -m 700 "$staging"
      /bin/cp -R "$wanted" "$staged"
      /usr/sbin/chown -R root:wheel "$staged"
      /usr/bin/codesign --verify --strict --deep "$staged" ||
        fail "the signature of $staged does not verify"
      id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staged/Contents/Info.plist")
      [[ $id == bar.esko.Ghostty ]] || fail "$staged has bundle identifier $id, not bar.esko.Ghostty"
      [[ "$(/usr/bin/stat -f %d "$staging")" == "$(/usr/bin/stat -f %d /Applications)" ]] ||
        fail "$state and /Applications are on different volumes, so one rename cannot move the app"

      installed=$(identity "$staged")
      result=$(${swap}/bin/ghostty-swap "$staged" "$target") ||
        fail "could not put the app at $target. If the reason is \"Operation not permitted\", allow your terminal in System Settings > Privacy & Security > App Management, then deploy again"
      [[ "$(identity "$target")" == "$installed" ]] ||
        fail "$target is not the bundle just installed"
      printf '%s %s\n' "$wanted" "$installed" > "$marker.new"
      /bin/mv -f "$marker.new" "$marker"

      /bin/rm -rf "$state/previous"
      if [[ $result == swapped ]]; then
        /bin/mkdir -m 700 "$state/previous"
        /bin/mv "$staged" "$state/previous/Ghostty.app"
      fi
      /bin/rmdir "$staging"
      echo "installed Ghostty ${release.version}" >&2
    )
  '';

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
