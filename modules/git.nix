{ pkgs, ... }:
{
  # nix-darwin needs the home dir to locate HM's target.
  users.users.jooize.home = "/Users/jooize";

  # gh as a SYSTEM package -> /run/current-system/sw/bin: root-owned, on PATH,
  # pinned to flake.lock, gcroot-protected. Not user-writable, so no
  # write-to-execute surface (the whole point vs a ~/.nix-profile bin).
  # gitleaks is load-bearing, not convenience: claude-init's generated
  # .githooks/pre-commit scans the staged changes with it and REFUSES the commit
  # when it cannot be found (fail closed).
  environment.systemPackages = [ pkgs.gh pkgs.gitleaks ];

  # git config, declarative via home-manager. The generated ~/.config/git/config
  # is a read-only symlink into the store - config, never on PATH, never executed.
  # No home.packages, so HM adds nothing to PATH at all.
  home-manager.users.jooize = {
    home.stateVersion = "26.05";  # VERIFY: match your nixpkgs release

    programs.git = {
      enable = true;
      # Global ignore (HM generates ~/.config/git/ignore): personal-tool / OS
      # artifacts that recur across every repo, kept out of each project's own
      # .gitignore. Replaces the former hand-maintained ~/.config/git/ignore.
      ignores = [
        ".DS_Store"
        ".tmp/"
        ".trash/"
        "*.bak"
        ".claude-lane"
        ".claude-devcontainer/"
        ".agents-cargo/"
        ".agents-work/"
        ".claude-memory/"
        ".claude-sessions/"
        ".claude-history/"
        ".claude-plans/"
        # **/ needed: the internal slash would otherwise anchor this to the repo root
        "**/.claude/settings.local.json"
      ];
      # HM master unified user/email/raw config under `settings`
      # (was userName / userEmail / extraConfig). settings maps 1:1 to git config.
      settings = {
        init.defaultBranch = "main";
        user = {
          name = "Tilde Esko";
          email = "tilde@esko.bar";
        };
        # Empty first element resets any inherited helper (e.g. the system
        # osxkeychain from Xcode's gitconfig) so github.com uses gh only.
        credential = {
          "https://github.com".helper = [ "" "!gh auth git-credential" ];
          "https://gist.github.com".helper = [ "" "!gh auth git-credential" ];
        };
      };
    };
  };
}
