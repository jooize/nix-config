{ ... }:
{
  security.locked = {
    enable = true;
    user = "jooize";
    # Declarative id (users.knownUsers). First free in the hidden
    # 400-499 range at declaration time: 401 is _jooize-pinned, 402 is
    # _pinned-clones, 441 is _oahd.
    uid = 403;
  };
}
