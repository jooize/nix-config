{ ... }:
{
  security.locked = {
    enable = true;
    user = "jooize";
    # First free id in the hidden 400-499 service range at declaration
    # time (2026-08-06): 401 is _jooize-pinned, 402 is _pinned-clones,
    # 441 is _oahd. The script's "401 reserved for lock" comment predates
    # pinned's deployment and is stale on this machine.
    uid = 403;
  };
}
