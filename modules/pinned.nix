{ ... }:
{
  security.pinned = {
    enable = true;
    users = [ "jooize" ];
    # Declarative gids, adopting the ids the imperative allocator picked
    # when these groups were first created live (verified via dscl
    # 2026-08-06) -- nix-darwin adopts an existing group when the gid
    # matches, so this is a no-op takeover, not a recreation.
    gids = {
      "_jooize-pinned" = 401;
    };
  };
}
