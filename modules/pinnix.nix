{ ... }:
{
  # The Nix consumer of pinned's record: deploy, upgrade, add. Same users
  # as security.pinned -- a round pinnix drives runs pinned's ceremonies as
  # root on their behalf. Declarative gid, next free in the hidden service
  # range after 401 _jooize-pinned, 402 _pinned-clones (pinned's old clone
  # group, dropped by hand once pinned's module stops declaring it), 403
  # _jooize-lock.
  security.pinnix = {
    enable = true;
    users = [ "jooize" ];
    gids = {
      "_pinnix-clones" = 404;
    };
  };
}
