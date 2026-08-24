# Thin root-owned anchor -- template for /etc/nix-darwin/flake.nix.
#
# Its only job is naming inputs. All configuration lives in the nix-config
# input, which is deliberately input-free and cannot pin itself.
#
# The `rev=` lines are trust decisions. They are synced from the root-owned
# pins under /var/db/pinned by `pinned deploy` -- NEVER hand-edit a rev. Edit
# this file (via sudo) only to change the input SET.
#
# Install once, by hand, keeping the existing /etc/nix-darwin/flake.lock:
#
#     sudo cp anchor/flake.nix /etc/nix-darwin/flake.nix
#
# Nix appends the nix-config lock node on the next root rebuild; every other
# node stays locked exactly as it is.
#
# Never make /etc/nix-darwin a symlink into the user-writable repo -- that
# would hand the config root builds to anything running as the user.
#
# One sibling data file lives beside this one: claude/claude-pin.json, the
# root-owned Claude version pin (nix-config points claude.pinFile at
# "${inputs.self}/claude/claude-pin.json", i.e. THIS directory's store copy).
# It is written only by `sudo claude-pin-write`, via `claude-update-nix`, which
# PGP-verifies the release and refuses downgrades. Two consequences:
#   - /etc/nix-darwin must NEVER become a git repo: a git flake sees only
#     tracked files, so the untracked pin would vanish from the store copy and
#     eval would throw the bootstrap message.
#   - a Claude version bump is a root file write + rebuild, not a repo commit,
#     review round, or rev bump.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sudowhat = {
      url = "git+file:///Users/jooize/Projects/sudowhat?ref=refs/heads/main&rev=dd9adf87af58481911fdedb382ebc3fb04c4f047";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-hardening = {
      url = "git+file:///Users/jooize/Projects/claude-code-hardening?dir=nix&ref=refs/heads/main&rev=9b9e3c7c0149e9f7905385b7c2b89ff0cf9a770a";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pinned = {
      url = "git+file:///Users/jooize/Projects/pinned?ref=refs/heads/main&rev=f61ace9344dc9fa88cd4e4f6ed609a5c890a24ac";
    };
    # All-zero placeholder, same mechanism as nix-config below: recognized
    # by deploy's rev grammar, unfetchable until the first `pinned deploy`
    # syncs the blessed rev in. locked's flake is input-free.
    locked.url = "git+file:///Users/jooize/Projects/locked?ref=refs/heads/main&rev=0000000000000000000000000000000000000000";
    # The all-zero rev is a deliberate placeholder, not a pin. It matches the
    # rev grammar deploy scans for, so the input is recognized and synced from
    # the root-owned pin before anything evaluates; and it can never be
    # fetched, so a bare darwin-rebuild between installing this anchor and the
    # first deploy fails closed instead of building an author-chosen tree. Run
    # `pinned approve ~/Projects/nix-config` then `pinned deploy` to fill it.
    nix-config.url = "git+file:///Users/jooize/Projects/nix-config?ref=refs/heads/main&rev=0000000000000000000000000000000000000000";
  };
  outputs = inputs: inputs.nix-config.lib.mkOutputs inputs;
}
