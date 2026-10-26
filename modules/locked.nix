{ ... }:
{
  security.locked = {
    enable = true;
    user = "jooize";
    # Every 2 minutes instead of the default 15. A run costs about 2 s of
    # CPU (measured 2026-09-15 through sudo, so an upper bound), and the
    # status reads as stale after three intervals, so an open locked
    # ceremony (which pauses the timer) shows stale after 6 minutes.
    verifyInterval = 120;
  };
}
