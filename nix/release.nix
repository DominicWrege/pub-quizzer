{
  lib,
  beamPackages,
  sqlite,
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
in
beamPackages.mixRelease {
  inherit
    pname
    version
    src
    mixFodDeps
    ;

  # exqlite (SQLite NIF) needs a HOME dir for elixir_make's cache,
  # and the sqlite amalgamation headers to compile from source (no network
  # in the sandbox, so the precompiled NIF download must fall back to source).
  nativeBuildInputs = [ sqlite ];

  preConfigure = ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
  '';

  # The committed assets in priv/static are already minified by esbuild/tailwind.
  # phx.digest regenerates the digested + gzipped copies for the release.
  postBuild = ''
    mix phx.digest --no-deps-check
  '';
}
