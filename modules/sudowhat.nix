{ ... }:
{
  services.sudowhat.enable = true;
  services.sudowhat.nonConsole = "deny";
  services.sudowhat.verifyStyle = "random";
  services.sudowhat.echoColor = "anomalies";
  services.sudowhat.auditDisplay = "on";
}
