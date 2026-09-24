# Environment names that make bash run code or change behaviour at startup, before
# a script's first line: BASH_ENV and ENV name a file to source, SHELLOPTS and
# BASHOPTS turn on options (xtrace), PS4 is expanded (with command substitution)
# for every traced line. Exported functions travel as BASH_FUNC_<name>%%.
# Any process running as the user can pre-set these for GUI-launched shells
# (launchctl setenv), and every bash script started below that shell would obey
# them. The fish shim (fish.nix) and /etc/zshenv (xdg.nix) remove them.
{
  names = [ "BASH_ENV" "ENV" "SHELLOPTS" "BASHOPTS" "PS4" ];
  prefixes = [ "BASH_FUNC_" ];
}
