# nix-config

Source-of-truth nix-darwin configuration for this Mac. The root-owned anchor at
`/etc/nix-darwin/flake.nix` consumes this repo as a rev-pinned `git+file` input,
the same way it consumes sudowhat, claude-code-hardening, and pinned.

This flake declares **no inputs**. Inputs — and their `rev=` pins, each of which
is a trust decision — live only in the root-owned anchor, which passes its
resolved inputs to `lib.mkOutputs`. A user-writable repo never picks its own pins.

## Layout

    flake.nix          input-free; exports lib.mkOutputs
    modules/           lix, sudowhat, git, pinned
    claude/            claude-pin.json (read at eval time)
    anchor/flake.nix   template for the root-owned /etc/nix-darwin/flake.nix

## Workflow

Daily path — the rebuild is gated, not run by hand:

    edit → commit → pinned approve ~/Projects/nix-config → pinned deploy

`pinned upgrade` does approve + deploy for every stale input in one elevation.

For a dry run before committing, point a scratch anchor at this working rev and
`darwin-rebuild build --flake <scratch-anchor>`. That is a debugging aid, not the
daily path — it builds without going through the pin ceremony.

## Identity invariant

`darwinConfigurations.<attr>` must equal `networking.localHostName`. Both
`darwin-rebuild` and `pinned deploy` (which invokes it attr-less) resolve the
configuration via `scutil --get LocalHostName`, so an attr that does not match
live state makes an attr-less rebuild fail outright. The config declares both
`localHostName` and `computerName`, so activation converges drift — macOS
rewrites `LocalHostName` on LAN name collisions — back to the declared name. The
attr and the declaration come from a single binding in `flake.nix`; keep it that
way. `networking.hostName` is deliberately unset, leaving the DHCP/DNS-derived
hostname unmanaged.

## Never symlink /etc/nix-darwin here

`/etc/nix-darwin` must stay a root-owned directory holding a real file. A
root-owned symlink into this user-writable repo would let anything running as the
user rewrite the config that root builds — re-enabling un-gated sudo rebuilds and
defeating the entire pinned ceremony. Install the anchor by copying it:

    sudo cp anchor/flake.nix /etc/nix-darwin/flake.nix

once, by hand, keeping the existing `flake.lock`. The template ships nix-config's
rev as all zeros, so the bootstrap order is forced and the gate is exercised on
day one:

    pinned approve ~/Projects/nix-config → pinned deploy

Until that runs, the anchor cannot evaluate — a premature rebuild fails closed
rather than building whatever rev an author happened to stamp. Thereafter
`pinned deploy` is the only writer of real revs; hand-edit the anchor (via sudo)
only to change the input *set*.
