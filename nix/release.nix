{
  lib,
  pkgs,
  beamPackages,
  sqlite,
  nodejs,
  esbuild,
}:

let
  pname = "pub_quizzer";
  version = "0.1.9";
  src = ./..;

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "mix-deps-${pname}";
    inherit src version;
    hash = "sha256-iJjyAEqnvd6sZW4L5edgAIWjpOo8aNyKdQZ/jbaTv7o=";
    mixEnv = "prod";
  };

  pnpmDeps = pkgs.fetchPnpmDeps {
    pname = "${pname}-pnpm-deps";
    inherit version;
    src = lib.cleanSourceWith {
      src = ./../assets;
      filter = path: type:
        let name = lib.baseNameOf path;
        in name != ".git" && name != "node_modules";
    };
    hash = "sha256-9jCIPhBYyTq6sAn/DAlpJbWMZTMYocEIyxaYdUWc2hE=";
    fetcherVersion = 4;
  };
in
beamPackages.mixRelease {
  inherit
    pname
    version
    src
    mixFodDeps
    ;

  nativeBuildInputs = [
    sqlite
    nodejs
    esbuild
    pkgs.pnpm
    pkgs.pnpmConfigHook
  ];

  preConfigure = ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
    # pnpmConfigHook (postConfigure) reads these to install assets/ deps offline.
    export pnpmDeps="${pnpmDeps}"
    export pnpmRoot="assets"
  '';

  postBuild = ''
    # Build frontend assets from source — no reliance on committed minified files.
    # node_modules was populated by pnpmConfigHook during configurePhase.

    # CSS: Tailwind v4 CLI (from the offline node_modules), scans lib/** + assets/**
    ./assets/node_modules/.bin/tailwindcss \
      --input=assets/css/app.css \
      --output=priv/static/assets/css/app.css \
      --minify

    # JS: resolve Phoenix dependencies and compiled colocated hooks.
    NODE_PATH="$PWD/deps:$PWD/_build/prod" esbuild assets/js/app.ts \
      --bundle --minify --target=es2017 \
      --outdir=priv/static/assets/js --entry-names=app

    # Digest for cache-busting
    mix phx.digest --no-deps-check
  '';
}
