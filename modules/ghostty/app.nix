# The patched Ghostty app (jooize/ghostty, branch jooize) exactly as its
# release job published it: built and signed ad hoc in CI, attested there,
# and pinned here by hash. Nothing is rebuilt; the zip is unpacked as is.
#
# `zip` and `manifest` are the release's Ghostty.app.zip and manifest.txt.
# The manifest lists every file's sha256 and every link's target; the
# install check recomputes it from the unpacked app and requires an exact
# match, so an unpacking difference (a lost link, a changed byte) fails the
# build instead of landing in /Applications.
{ stdenvNoCC, unzip, version, zip, manifest }:

stdenvNoCC.mkDerivation {
  pname = "ghostty-hardened";
  inherit version;

  src = zip;
  nativeBuildInputs = [ unzip ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  # The app is signed: stripping, patching shebangs or rewriting install
  # names would change signed bytes.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    unzip -q "$src" -d "$out/Applications"
    runHook postInstall
  '';

  doInstallCheck = true;
  # Same format as the release job's "Write manifest and archive" step: one
  # line per file, sha256 or "link:<target>", two spaces, path, sorted by
  # byte value.
  installCheckPhase = ''
    runHook preInstallCheck
    cd "$out/Applications"
    entries=(*)
    if [[ ''${#entries[@]} -ne 1 || ''${entries[0]} != Ghostty.app ]]; then
      echo "the zip holds more than Ghostty.app: ''${entries[*]}" >&2
      exit 1
    fi
    find Ghostty.app \( -type f -o -type l \) -print0 | LC_ALL=C sort -z |
      while IFS= read -r -d "" f; do
        if [[ -L $f ]]; then
          printf 'link:%s  %s\n' "$(readlink "$f")" "$f"
        else
          printf '%s  %s\n' "$(sha256sum < "$f" | cut -d' ' -f1)" "$f"
        fi
      done > "$NIX_BUILD_TOP/manifest.txt"
    if ! diff -u ${manifest} "$NIX_BUILD_TOP/manifest.txt" >&2; then
      echo "the unpacked app does not match the release manifest" >&2
      exit 1
    fi
    cd "$NIX_BUILD_TOP"
    runHook postInstallCheck
  '';
}
