{
  description = "Kneipenquiz - realtime pub quiz app for teams";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
    in
    {
      # --- NixOS module (consumed by a server configuration) ---
      nixosModules.default = import ./nix/module.nix;

      # --- Release packages ---
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = self.packages.${system}.pub-quizzer;
          pub-quizzer = pkgs.callPackage ./nix/release.nix { };
        }
      );

      # --- Dev shell (original, for local development) ---
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
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
        }
      );
    };
}
