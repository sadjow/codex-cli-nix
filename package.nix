{ lib
, stdenv
, fetchurl
, nodejs_22
, cacert
, bash
}:

let
  version = "1.0.0";
  
  codexTarball = fetchurl {
    url = "https://registry.npmjs.org/@openai/codex-cli/-/codex-cli-${version}.tgz";
    sha256 = "0000000000000000000000000000000000000000000000000000";
  };
in
stdenv.mkDerivation rec {
  pname = "codex-cli";
  inherit version;

  dontUnpack = true;

  nativeBuildInputs = [ 
    nodejs_22
    cacert
  ];
  
  buildPhase = ''
    export HOME=$TMPDIR
    mkdir -p $HOME/.npm
    
    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export NODE_EXTRA_CA_CERTS=$SSL_CERT_FILE
    
    ${nodejs_22}/bin/npm config set cafile $SSL_CERT_FILE
    
    ${nodejs_22}/bin/npm config set offline true
    
    ${nodejs_22}/bin/npm install -g --prefix=$out ${codexTarball}
  '';

  installPhase = ''
    rm -f $out/bin/codex
    
    mkdir -p $out/bin
    cat > $out/bin/codex << 'EOF'
    #!${bash}/bin/bash
    export NODE_PATH="$out/lib/node_modules"
    
    export CODEX_EXECUTABLE_PATH="$HOME/.local/bin/codex"
    
    export DISABLE_AUTOUPDATER=1
    
    export _CODEX_NPM_WRAPPER="$(mktemp -d)/npm"
    cat > "$_CODEX_NPM_WRAPPER" << 'NPM_EOF'
    #!${bash}/bin/bash
    if [[ "$1" = "update" ]] || [[ "$1" = "outdated" ]] || [[ "$1" = "view" && "$2" =~ @openai/codex-cli ]]; then
        echo "Updates are managed through Nix. Current version: ${version}"
        exit 0
    fi
    exec ${nodejs_22}/bin/npm "$@"
    NPM_EOF
    chmod +x "$_CODEX_NPM_WRAPPER"
    
    export PATH="$(dirname "$_CODEX_NPM_WRAPPER"):$PATH"
    
    exec ${nodejs_22}/bin/node --no-warnings --enable-source-maps "$out/lib/node_modules/@openai/codex-cli/cli.js" "$@"
    EOF
    chmod +x $out/bin/codex
    
    substituteInPlace $out/bin/codex \
      --replace '$out' "$out"
  '';

  meta = with lib; {
    description = "OpenAI Codex CLI - AI coding assistant in your terminal";
    homepage = "https://developers.openai.com/codex/cli";
    license = licenses.unfree;
    platforms = platforms.all;
  };
}