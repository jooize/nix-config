{ ... }:
{
  security.locked = {
    enable = true;
    user = "jooize";
    # No uid here on purpose: the module allocates the first free id in
    # the hidden 401-499 range at activation (403 on this machine today;
    # 401 is _jooize-pinned, 402 is _pinned-clones, 441 is _oahd).
  };
}
