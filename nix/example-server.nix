# Example: wiring pub-quizzer into a NixOS server configuration.
#
# Copy the relevant pieces into your server's config. Adjust the domain,
# GitHub repo, and secret paths. See nix/deploy.md for full instructions.

{ inputs, pkgs, ... }:

{
  # Import the NixOS module
  imports = [
    inputs.pub-quizzer.nixosModules.default
  ];

  services.pub-quizzer = {
    enable = true;
    domain = "quizforabetterlife.eu";

    # Single env file holding ALL app config + secrets:
    #   SECRET_KEY_BASE=<mix phx.gen.secret>
    #   RELEASE_COOKIE=<random string>
    #   RESEND_API_KEY=<key from resend.com/api-keys>
    #   MAIL_FROM=noreply@quizforabetterlife.eu
    #   DATABASE_PATH=/var/lib/pub-quizzer/pub_quizzer.db
    environmentFile = "/var/lib/pub-quizzer/secrets/env";
  };
}
