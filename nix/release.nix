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
  version = "0.1.0";
  src = ./..;

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "mix-deps-${pname}";
    inherit src version;
    hash = "sha256-P6S8MbQTAi7bSeTZl2n08BRxK2H+AjJO8cTdkXuYT3s=";
    mixEnv = "prod";
  };

  npmDeps = pkgs.fetchNpmDeps {
    pname = "${pname}-npm-deps";
    inherit version;
    src = lib.cleanSourceWith {
      src = ./../assets;
      filter = path: _type:
        let
          name = builtins.baseNameOf path;
        in
        name == "package.json" || name == "package-lock.json";
    };
    hash = "sha256-9ZHcx297KjPbZGROrBlNkdHl0Ebt9OdHXqr+IfGR5UY=";
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
  ];

  preConfigure = ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
  '';

  postBuild = ''
    # Build frontend assets from source — no reliance on committed minified files.
    # fetchNpmDeps produces an npm *cache* (_cacache); populate node_modules
    # offline from it. Drop any dev node_modules copied into the build tree first.
    npm_cache="$(mktemp -d)"
    cp -a ${npmDeps}/_cacache "$npm_cache"/
    chmod -R u+w "$npm_cache"
    rm -rf assets/node_modules
    (
      cd assets
      npm ci --offline --no-audit --no-fund --ignore-scripts --cache "$npm_cache"
    )
    # .bin shims use `#!/usr/bin/env node`, which doesn't exist in the sandbox;
    # rewrite them to the nix-store node so the tailwindcss CLI is runnable.
    patchShebangs assets/node_modules

    # CSS: Tailwind v4 CLI (from the offline node_modules), scans lib/** + assets/**
    ./assets/node_modules/.bin/tailwindcss \
      --input=assets/css/app.css \
      --output=priv/static/assets/css/app.css \
      --minify

    # JS: esbuild (from nixpkgs); NODE_PATH=deps resolves phoenix_live_view JS
    NODE_PATH="$PWD/deps" esbuild assets/js/app.ts \
      --bundle --minify --target=es2017 \
      --outdir=priv/static/assets/js --entry-names=app

    # Digest for cache-busting
    mix phx.digest --no-deps-check
  '';
}
