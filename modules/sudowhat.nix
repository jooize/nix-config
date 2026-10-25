{ ... }:
{
  services.sudowhat.enable = true;
  services.sudowhat.nonConsole = "nopasswd-only";
  services.sudowhat.echoColor = "on";
  services.sudowhat.auditDisplay = "on";
}
