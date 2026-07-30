{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.pub-quizzer;
in
{
  options.services.pub-quizzer = {
    enable = lib.mkEnableOption "Pub-Quizzer realtime pub quiz app";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The pub-quizzer release package to use. Pass from flake inputs: inputs.pub-quizzer.packages.\${pkgs.stdenv.hostPlatform.system}.pub-quizzer";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        systemd EnvironmentFile holding all secrets, one KEY=value per line:

            SECRET_KEY_BASE=<mix phx.gen.secret>
            RELEASE_COOKIE=<random string>
            RESEND_API_KEY=<key from resend.com/api-keys>
            MAIL_FROM=noreply@quizforabetterlife.eu
            DATABASE_PATH=/var/lib/pub-quizzer/pub_quizzer.db
      '';
    };

    domain = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Domain to serve the app on. When set, the module automatically
        configures Caddy as a reverse proxy with auto-HTTPS.
        Set to null if you manage the reverse proxy yourself.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4080;
      description = "Port the Bandit HTTP server listens on.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.pub-quizzer = {
      isSystemUser = true;
      group = "pub-quizzer";
      home = "/var/lib/pub-quizzer";
      createHome = true;
    };
    users.groups.pub-quizzer = { };

    systemd.tmpfiles.rules = [
      "d /var/lib/pub-quizzer 0750 pub-quizzer pub-quizzer -"
    ];

    systemd.services.pub-quizzer = {
      description = "Pub-Quizzer realtime pub quiz app";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        PHX_SERVER = "true";
        PORT = toString cfg.port;
      } // lib.optionalAttrs (cfg.domain != null) {
        PHX_HOST = cfg.domain;
      };

      serviceConfig = {
        User = "pub-quizzer";
        Group = "pub-quizzer";
        WorkingDirectory = "/var/lib/pub-quizzer";
        Restart = "on-failure";
        RestartSec = 5;

        ExecStartPre = let
          migrate = pkgs.writeShellScript "pub-quizzer-migrate" ''
            ${cfg.package}/bin/pub_quizzer eval "PubQuizzer.Release.migrate()"
          '';
        in "${migrate}";

        ExecStart = "${cfg.package}/bin/pub_quizzer start";
        EnvironmentFile = cfg.environmentFile;

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/pub-quizzer" ];
      };
    };

    # Auto-configure Caddy reverse proxy when domain is set
    services.caddy = lib.mkIf (cfg.domain != null) {
      enable = lib.mkDefault true;
      virtualHosts.${cfg.domain}.extraConfig = ''
        reverse_proxy localhost:${toString cfg.port}
      '';
    };
  };
}
