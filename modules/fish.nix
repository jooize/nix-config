{ pkgs, ... }:
let
  user = "jooize";
  perUser = "/etc/profiles/per-user/${user}";

  # Root-owned constructor of the interactive environment. The fish-shim
  # launches every fish as `fish --no-config --init-command 'source <this>'`:
  # under --no-config fish reads NO user-writable startup surface (config.fish,
  # conf.d, universal variables, user function autoload -- verified on fish
  # 4.7.1), so this store file is the only startup code. It therefore builds
  # the environment itself instead of trusting whatever the spawning chain
  # left in it.
  #
  # PATH is explicit, root-owned profiles only, per-user first. ~/.nix-profile
  # (nix's user-imperative profile) is deliberately ABSENT: the nix daemon
  # lets the user populate it WITHOUT root (`nix profile install`), and the
  # conventional order nix-darwin bakes into set-environment puts it ahead of
  # every root-owned bin -- an interposition slot in front of both shims. On
  # this machine it is a dangling symlink (no profile ever created), so
  # dropping it loses nothing.
  fishInit = pkgs.writeText "fish-init.fish" ''
    set -gx PATH ${perUser}/bin /run/current-system/sw/bin /nix/var/nix/profiles/default/bin /usr/local/bin /usr/bin /bin /usr/sbin /sbin

    # Parity with nix-darwin's set-environment, minus every ~/.nix-profile
    # entry (and minus the ~/.nix-defexpr/channels NIX_PATH prepend -- also
    # user-writable, and unused with flakes).
    set -gx EDITOR nano
    set -gx PAGER "less -R"
    set -gx NIX_SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
    set -gx NIX_PATH "nixpkgs=flake:nixpkgs:/nix/var/nix/profiles/per-user/root/channels"
    set -gx NIX_USER_PROFILE_DIR /nix/var/nix/profiles/per-user/${user}
    set -gx NIX_PROFILES "/nix/var/nix/profiles/default /run/current-system/sw ${perUser}"
    set -gx TERMINFO_DIRS ${perUser}/share/terminfo:/run/current-system/sw/share/terminfo:/nix/var/nix/profiles/default/share/terminfo:/usr/share/terminfo
    set -gx XDG_CONFIG_DIRS ${perUser}/etc/xdg:/run/current-system/sw/etc/xdg:/nix/var/nix/profiles/default/etc/xdg
    set -gx XDG_DATA_DIRS ${perUser}/share:/run/current-system/sw/share:/nix/var/nix/profiles/default/share

    # Child zsh/bash source /etc/zshenv and /etc/bashrc, whose set-environment
    # call is guarded by this flag. Setting it keeps children on THIS PATH
    # instead of letting set-environment re-prepend ~/.nix-profile/bin.
    set -gx __NIX_DARWIN_SET_ENVIRONMENT_DONE 1

    source ${./fish/normalize-pwd-case.fish}

    # Ghostty shell integration (title, path reporting, tab cwd inheritance)
    # normally loads via an injected XDG_DATA_DIRS entry picked up by vendor
    # conf.d -- both removed here (--no-config skips vendor conf.d, and this
    # init sets XDG_DATA_DIRS itself). Source it by its FIXED bundle path:
    # the bundle is root-owned by ceremony, whereas the injected route
    # (GHOSTTY_SHELL_INTEGRATION_XDG_DIR) is an attacker-settable env var.
    if test "$TERM_PROGRAM" = ghostty
        set -l ghostty_si /Applications/Ghostty.app/Contents/Resources/ghostty/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
        test -r "$ghostty_si"; and source "$ghostty_si"
    end
  '';

  # Same-name PATH interpose, claude-shim pattern (claude-code-hardening
  # nix/claude-code.nix): the real file is bin/fish-shim -- the honest
  # artifact name, so `which fish-shim` resolves -- and bin/fish is a symlink
  # to it. The package lands in the root-owned per-user profile, which PATH
  # puts ahead of the system profile's real fish, so every `fish` this user
  # resolves goes through here. Ghostty's command points at
  # ${perUser}/bin/fish explicitly.
  fishShimScript = pkgs.writeShellScript "fish-shim" ''
    exec ${pkgs.fish}/bin/fish --no-config --init-command 'source ${fishInit}' "$@"
  '';
  fishShim = pkgs.runCommand "fish-shim" { } ''
    mkdir -p $out/bin
    install -m755 ${fishShimScript} $out/bin/fish-shim
    ln -s fish-shim $out/bin/fish
  '';
in
{
  programs.fish.enable = true;

  # Real fish for /etc/shells plus the per-user shim path, so a later
  # `chsh -s ${perUser}/bin/fish` ceremony is possible (chsh refuses shells
  # not listed here; listing grants nothing by itself).
  environment.shells = [ pkgs.fish "${perUser}/bin/fish" ];

  users.users.${user}.packages = [ fishShim ];
}
