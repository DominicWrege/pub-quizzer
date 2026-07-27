{
  description = "Kneipenquiz - realtime pub quiz app for teams";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            beamPackages.elixir
            beamPackages.erlang
            sqlite
            inotify-tools
            watchman
            nodejs
            uv
            (writeShellScriptBin "dev" "exec mix phx.server $@")
          ];

          # Playwright E2E testing (see e2e/ and playwright.config.ts).
          # nixpkgs' playwright-driver bundles the driver; `.browsers` is a
          # linkFarm with chromium/firefox/webkit/ffmpeg at the revisions
          # matching the pinned @playwright/test version. We point the npm
          # package at the Nix-managed browsers and skip its own download.
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
        };
      });
}
