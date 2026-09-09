{ lib, pkgs, ... }:
let
  user = "jooize";
  perUser = "/etc/profiles/per-user/${user}";

  # XDG relocation vars, shared with xdg.nix (set-environment + launchd).
  # Rendered here because the shim skips set-environment by design; exported
  # (-gx) so fish-spawned zsh/bash inherit them too -- their set-environment
  # is guard-skipped, and ZDOTDIR must survive into child zsh.
  xdgLines = lib.concatStringsSep "\n    " (
    lib.mapAttrsToList (n: v: ''set -gx ${n} "${v}"'') (import ./xdg-env-vars.nix)
  );

  # fish's default theme, verbatim from share/fish/themes/default.theme
  # (fish 4.7.1), one `set -g` per line. Palette names only, so the
  # terminal theme decides what each colour looks like on its background.
  themeLines = lib.concatStringsSep "\n    " (map (l: "set -g ${l}") [
    "fish_color_normal --reset"
    "fish_color_autosuggestion brblack"
    "fish_color_cancel -r"
    "fish_color_command --reset"
    "fish_color_comment red"
    "fish_color_cwd green"
    "fish_color_cwd_root red"
    "fish_color_end green"
    "fish_color_error brred"
    "fish_color_escape brcyan"
    "fish_color_history_current --bold"
    "fish_color_host --reset"
    "fish_color_host_remote yellow"
    "fish_color_operator brcyan"
    "fish_color_param cyan"
    "fish_color_quote yellow"
    "fish_color_redirection cyan --bold"
    "fish_color_search_match white --background=brblack --bold"
    "fish_color_selection white --background=brblack --bold"
    "fish_color_status red"
    "fish_color_user brgreen"
    "fish_color_valid_path --underline"
    "fish_pager_color_description yellow --italics"
    "fish_pager_color_prefix --bold --underline"
    "fish_pager_color_progress brwhite --background=cyan --bold"
    "fish_pager_color_selected_background -r"
  ]);

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

    ${xdgLines}

    # Colours. --no-config skips universal variables, which is where fish
    # keeps its theme, so prompt and highlighting came up plain. These are
    # the values of fish's shipped default theme (share/fish/themes/
    # default.theme, fish 4.7.1), set as globals here. Not `fish_config theme
    # choose`: that looks under ~/.config/fish/themes before the store.
    ${themeLines}

    # Child zsh/bash source /etc/zshenv and /etc/bashrc, whose set-environment
    # call is guarded by this flag. Setting it keeps children on THIS PATH
    # instead of letting set-environment re-prepend ~/.nix-profile/bin.
    set -gx __NIX_DARWIN_SET_ENVIRONMENT_DONE 1

    source ${./fish/normalize-pwd-case.fish}

    # Ghostty shell integration (title, path reporting, prompt marks, tab cwd
    # inheritance) normally loads via an injected XDG_DATA_DIRS entry picked
    # up by vendor conf.d -- both removed here (--no-config skips vendor
    # conf.d, and this init sets XDG_DATA_DIRS itself). Source it by its FIXED
    # bundle path, never via GHOSTTY_RESOURCES_DIR or
    # GHOSTTY_SHELL_INTEGRATION_XDG_DIR: any user process can plant those
    # (launchctl setenv) to point at a writable file.
    #
    # The path is trusted only if every component is root-owned and none is
    # a symlink. /Applications is admin-writable, so a user process could
    # rename the bundle away and plant a replacement under the same name; it
    # cannot make that replacement root-owned, and a symlink into some
    # root-owned tree elsewhere (the nix store) is refused outright. A skip
    # is reported, not silent: the integration's own setup function erases
    # itself after the first prompt, so its absence is otherwise invisible.
    # /usr/bin/stat by absolute path: a GNU stat on PATH reads -f as
    # "filesystem". No -L, so a symlink reports itself.
    if test "$TERM_PROGRAM" = ghostty
        set -l ghostty_si /Applications/Ghostty.app/Contents/Resources/ghostty/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish
        set -l node ""
        set -l reason ""
        for c in (string split / -- (string sub -s 2 -- $ghostty_si))
            set node "$node/$c"
            if test -L "$node"
                set reason "$node is a symlink"
            else if not test -e "$node"
                set reason "$node is missing"
            else if test "$(/usr/bin/stat -f %u "$node" 2>/dev/null)" != 0
                set reason "$node is not root-owned"
            end
            test -n "$reason"; and break
        end
        if test -z "$reason"
            source "$ghostty_si"
        else
            echo "fish-init: Ghostty shell integration skipped: $reason" >&2
        end
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
