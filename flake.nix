# Source-of-truth nix-darwin configuration for this Mac -- the "config meat".
#
# Consumed by the thin root-owned anchor at /etc/nix-darwin/flake.nix as a
# rev-pinned git+file input. This flake is deliberately INPUT-FREE: every input
# -- and every rev pin, each of which is a trust decision -- is declared by the
# root-owned anchor and synced from the root-owned /var/db/pinned slots by
# `pinned deploy`. A user-writable repo must never get to choose its own pins,
# so it names none; the anchor passes its own resolved inputs to mkOutputs.
{
  outputs = { self }: {
    lib.mkOutputs = inputs: {
      darwinConfigurations."Tildes-MacBook-Pro" = inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";  # change if Intel
        modules = [
          ./modules/lix.nix
          ./modules/sudowhat.nix
          ./modules/git.nix
          ./modules/pinned.nix
          inputs.sudowhat.darwinModules.default
          inputs.home-manager.darwinModules.home-manager
          inputs.claude-hardening.darwinModules.claude
          inputs.pinned.darwinModules.default
          {
            # Packages HM manages (if any) go to the ROOT-OWNED per-user profile
            # (/etc/profiles/per-user/jooize), never ~/.nix-profile - so nothing
            # user-writable ever lands on PATH. This is the security fix.
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "bak";  # lets HM take over ~/.config/git/config
          }
          ({ config, ... }: {
            claude.user = "jooize";
            claude.pinFile = ./claude/claude-pin.json;
            claude.patch.enable = true;
            # The container image and vm guest get the SAME derivation this
            # system installs -- byte-identical to what the sudoers
            # Digest_Spec commits to (pinned's readOnly package option).
            claude.pinnedPackage = config.security.pinned.package;
          })
          ({ pkgs, lib, ... }: {
            system.stateVersion = 5;
            nixpkgs.hostPlatform = "aarch64-darwin";
            # vm lane (claude-vm) needs tart (unfree FSL) + packer (unfree BUSL);
            # softnet is AGPL (free). Admit ONLY these two - everything else stays gated.
            nixpkgs.config.allowUnfreePredicate = pkg:
              builtins.elem (lib.getName pkg) [ "tart" "packer" ];
            programs.fish.enable = true;
            environment.shells = [ pkgs.fish ];
          })
        ];
      };
      apps = inputs.claude-hardening.apps;
    };
  };
}
