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
    lib.mkOutputs = inputs:
      let
        # darwin-rebuild (and pinned deploy, which invokes it attr-less)
        # resolves darwinConfigurations.$(scutil --get LocalHostName). Nothing
        # was holding that name steady: macOS rewrites LocalHostName on LAN
        # name collisions, and a rewrite silently breaks every attr-less
        # rebuild. Declaring it makes activation converge live state back to
        # this attr instead. The attr and the declaration must stay equal, so
        # both come from this one binding -- they cannot drift apart in source.
        #
        # The value is the live LocalHostName, verified UNSANDBOXED: under the
        # Seatbelt sandbox `scutil --get LocalHostName` cannot reach configd
        # and silently returns "MacBook-Pro", derived from ComputerName, with
        # no error. mDNS agrees with the real value (tildes-macbook-pro.local).
        localHostName = "Tildes-MacBook-Pro";
      in {
      darwinConfigurations.${localHostName} = inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";  # change if Intel
        modules = [
          ./modules/lix.nix
          ./modules/sudowhat.nix
          ./modules/environment.nix
          ./modules/git.nix
          ./modules/xdg.nix
          ./modules/fish.nix
          ./modules/pinned.nix
          ./modules/locked.nix
          ./modules/sudo.nix
          inputs.sudowhat.darwinModules.default
          inputs.home-manager.darwinModules.home-manager
          inputs.claude-hardening.darwinModules.claude
          inputs.pinned.darwinModules.default
          inputs.locked.darwinModules.default
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
            # The pin lives beside the ROOT-OWNED anchor, not in this repo:
            # `inputs.self` is /etc/nix-darwin (the flake actually being
            # evaluated), so pure eval can read it and nothing running as the
            # user can write it. Written only by `sudo claude-pin-write` via
            # `claude-update-nix`, which re-validates shape and refuses
            # downgrades; a version bump is therefore NOT a commit here.
            claude.pinFile = "${inputs.self}/claude/claude-pin.json";
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
          })
          {
            # Declared identity. networking.hostName is deliberately left unset:
            # the DHCP/DNS-derived hostname stays unmanaged.
            networking.localHostName = localHostName;
            networking.computerName = "MacBook Pro";
            # nix-darwin runs all activation as root and requires the target
            # user for per-user surfaces (launchd.user.envVariables in xdg.nix,
            # which already binds $HOME to this user) to be named explicitly.
            system.primaryUser = "jooize";
          }
        ];
      };
      apps = inputs.claude-hardening.apps;
    };
  };
}
