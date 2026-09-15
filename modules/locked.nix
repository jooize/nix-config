{ ... }:
{
  security.locked = {
    enable = true;
    user = "jooize";
    # Declarative id (users.knownUsers). First free in the hidden
    # 400-499 range at declaration time: 401 is _jooize-pinned, 402 is
    # _pinned-clones, 441 is _oahd.
    uid = 403;
    # Every 2 minutes instead of the default 15. A run costs about 2 s of
    # CPU (measured 2026-09-15 through sudo, so an upper bound), and the
    # status reads as stale after three intervals, so an open locked
    # ceremony (which pauses the timer) shows stale after 6 minutes.
    verifyInterval = 120;
  };
}
