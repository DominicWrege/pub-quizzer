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

          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

          shellHook = ''
            # Project-local venv for cicada-mcp (code indexer used by opencode).
            # Pins mcp<2 (mcp 2.x broke the cicada-mcp API contract).
            if [ ! -x .venv/bin/cicada-mcp ]; then
              echo "Setting up cicada-mcp venv..."
              uv venv .venv --quiet
              uv pip install --python .venv/bin/python "cicada-mcp" "mcp<2" --quiet
            fi
          '';
        };
      });
}
