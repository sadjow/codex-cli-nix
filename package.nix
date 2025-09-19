{ lib
, stdenv
, fetchurl
, nodejs_22
, makeWrapper
}:

stdenv.mkDerivation rec {
  pname = "codex";
  version = "0.39.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz";
    sha256 = "04kr4xdkc9rjcsk0159z2n0nznifg75sgjk3pi72mkih4m3rqnwn";
  };

  nativeBuildInputs = [ nodejs_22 makeWrapper ];

  installPhase = ''
    mkdir -p $out/lib/node_modules/@openai/codex
    cp -r . $out/lib/node_modules/@openai/codex
    
    mkdir -p $out/bin
    makeWrapper ${nodejs_22}/bin/node $out/bin/codex \
      --add-flags "$out/lib/node_modules/@openai/codex/bin/codex.js" \
      --prefix NODE_PATH : "$out/lib/node_modules"
  '';

  meta = with lib; {
    description = "OpenAI Codex CLI - AI coding assistant in your terminal";
    homepage = "https://github.com/openai/codex";
    license = licenses.unfree;
    platforms = platforms.all;
    mainProgram = "codex";
  };
}