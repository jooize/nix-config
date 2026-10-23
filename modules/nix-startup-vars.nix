# Environment names that change where nix reads its settings and flake
# registries, which daemon it talks to, or which command it runs, and that
# nix-darwin's set-environment never sets, so a login shell's rebuild of the
# environment does not replace them:
#   NIX_CONFIG            settings text, read after every nix.conf
#   NIX_USER_CONF_FILES   replaces the user nix.conf search path
#   NIX_CONF_DIR          replaces /etc/nix: its nix.conf and registry.json
#   NIX_REMOTE, NIX_DAEMON_SOCKET_PATH
#                         the store nix talks to, a socket any process could serve
#   NIX_SSHOPTS           options for every ssh nix starts (-oProxyCommand runs one)
#   NIX_PAGER             the command nix pipes long output through
# Any process running as the user can pre-set these for GUI-launched shells
# (launchctl setenv). The fish init (fish.nix) and /etc/zshenv (xdg.nix)
# remove them for every shell, login or not. The names nix reads that
# set-environment does set (XDG_CONFIG_HOME, XDG_CONFIG_DIRS, NIX_PATH,
# NIX_SSL_CERT_FILE) are rebuilt by every login shell instead.
{
  names = [
    "NIX_CONFIG"
    "NIX_USER_CONF_FILES"
    "NIX_CONF_DIR"
    "NIX_REMOTE"
    "NIX_DAEMON_SOCKET_PATH"
    "NIX_SSHOPTS"
    "NIX_PAGER"
  ];
}
