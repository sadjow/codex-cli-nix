{ lib
, stdenv
, fetchurl
, nodejs_22
, cacert
, bash
, patchelf
, gnutar
, gzip
, openssl
, libcap
, libz
, runtime ? "native"
, nativeBinName ? "codex"
, nodeBinName ? "codex-node"
}:

let
  version = "0.112.0";

  platformMap = {
    "aarch64-darwin" = "aarch64-apple-darwin";
    "x86_64-darwin" = "x86_64-apple-darwin";
    "x86_64-linux" = "x86_64-unknown-linux-gnu";
    "aarch64-linux" = "aarch64-unknown-linux-gnu";
  };

  nodePlatformMap = {
    "aarch64-darwin" = "darwin-arm64";
    "x86_64-darwin" = "darwin-x64";
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
  };

  platform = platformMap.${stdenv.hostPlatform.system} or null;
  nodePlatform = nodePlatformMap.${stdenv.hostPlatform.system} or null;

  nativeHashes = {
    "aarch64-apple-darwin" = "0f27s2ma8jjr8jl3jc7c9jc2s0a4pz6llqs4g1ir4924qzny7vhr";
    "x86_64-apple-darwin" = "0w4dpcvd0blgnrcci99b7js7iqfky982p11g5jivm9rqb07msvr5";
    "x86_64-unknown-linux-gnu" = "0vlvsx05qcrnma0fs4ygdc5wd9ypn0v50nsy28w107afzj5bj5lh";
    "aarch64-unknown-linux-gnu" = "1ajakb0kd7fnsa7ax88z3x8pbdscksdnidv79k6jibaaxp3w4iv3";
  };

  nodeOptionalDepHashes = {
    "darwin-arm64" = "0rxj4lccqxk85gnasfl15hd2f9mwx2jvl704ysmf8dymb0ldb3i8";
    "darwin-x64" = "0qbbs8119hpipmg819pm8bdrma5cpa1qz53bngklw94bayzsjr5p";
    "linux-x64" = "17lg1w9kjl0nrpngv4jvfqnpywj3m8hvnsrcahy0xfwrd2r9f9sq";
    "linux-arm64" = "0sjnjrh6sd7pkszf3dllxn393n2haskm9dj4ky92m2n3c10yqbl0";
  };

  nativeBinaryUrl = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${platform}.tar.gz";

  nativeBinary = if runtime == "native" && platform != null then
    fetchurl {
      url = nativeBinaryUrl;
      sha256 = nativeHashes.${platform};
    }
  else null;

  npmTarball = if runtime == "node" then
    fetchurl {
      url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz";
      sha256 = "16zadnzlic29fkgqxwdd53m73ybw9j5v73r7fvll0gnqbqc3zn8w";
    }
  else null;

  nodeOptionalDep = if runtime == "node" && nodePlatform != null then
    fetchurl {
      url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}-${nodePlatform}.tgz";
      sha256 = nodeOptionalDepHashes.${nodePlatform};
    }
  else null;

  runtimeConfig = {
    native = {
      nativeBuildInputs = [ gnutar gzip ] ++ lib.optionals stdenv.isLinux [ patchelf ];
      buildInputs = lib.optionals stdenv.isLinux [ openssl libcap libz ];
      description = "OpenAI Codex CLI (Native Binary) - AI coding assistant in your terminal";
      binName = nativeBinName;
    };
    node = {
      nativeBuildInputs = [ nodejs_22 cacert ];
      buildInputs = [];
      description = "OpenAI Codex CLI (Node.js) - AI coding assistant in your terminal";
      binName = nodeBinName;
    };
  };

  selected = runtimeConfig.${runtime};
in
assert runtime == "native" -> platform != null ||
  throw "Native runtime not supported on ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-darwin, x86_64-linux, aarch64-linux";

stdenv.mkDerivation rec {
  pname = if runtime == "native" then "codex" else "codex-${runtime}";
  inherit version;

  dontUnpack = true;

  dontPatchELF = runtime == "native";
  dontStrip = runtime == "native";

  nativeBuildInputs = selected.nativeBuildInputs;
  buildInputs = selected.buildInputs;

  buildPhase = if runtime == "native" then ''
    runHook preBuild
    mkdir -p build
    tar -xzf ${nativeBinary} -C build
    mv build/codex-${platform} build/codex
    chmod u+w,+x build/codex

    ${lib.optionalString stdenv.isLinux ''
    patchelf \
      --set-interpreter "$(cat ${stdenv.cc}/nix-support/dynamic-linker)" \
      --set-rpath "${lib.makeLibraryPath [ openssl libcap libz ]}" \
      build/codex
    ''}

    runHook postBuild
  '' else ''
    runHook preBuild
    export HOME=$TMPDIR
    mkdir -p $HOME/.npm

    export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
    export NODE_EXTRA_CA_CERTS=$SSL_CERT_FILE

    mkdir -p $out/lib/node_modules/@openai
    tar -xzf ${npmTarball} -C $out/lib/node_modules/@openai
    mv $out/lib/node_modules/@openai/package $out/lib/node_modules/@openai/codex

    ${lib.optionalString (nodeOptionalDep != null) ''
    tar -xzf ${nodeOptionalDep} -C $out/lib/node_modules/@openai
    mv $out/lib/node_modules/@openai/package $out/lib/node_modules/@openai/codex-${nodePlatform}
    ''}

    runHook postBuild
  '';

  installPhase = if runtime == "native" then ''
    runHook preInstall
    mkdir -p $out/bin

    cp build/codex $out/bin/codex-raw
    chmod +x $out/bin/codex-raw

    cat > $out/bin/${selected.binName} << 'WRAPPER_EOF'
#!${bash}/bin/bash
export CODEX_EXECUTABLE_PATH="$HOME/.local/bin/${selected.binName}"
export DISABLE_AUTOUPDATER=1
exec "$out/bin/codex-raw" "$@"
WRAPPER_EOF
    chmod +x $out/bin/${selected.binName}

    substituteInPlace $out/bin/${selected.binName} \
      --replace-fail '$out' "$out"
    runHook postInstall
  '' else ''
    runHook preInstall
    mkdir -p $out/bin

    cat > $out/bin/${selected.binName} << 'WRAPPER_EOF'
#!${bash}/bin/bash
export NODE_PATH="$out/lib/node_modules"
export CODEX_EXECUTABLE_PATH="$HOME/.local/bin/${selected.binName}"
export DISABLE_AUTOUPDATER=1

exec ${nodejs_22}/bin/node --no-warnings "$out/lib/node_modules/@openai/codex/bin/codex.js" "$@"
WRAPPER_EOF
    chmod +x $out/bin/${selected.binName}

    substituteInPlace $out/bin/${selected.binName} \
      --replace-fail '$out' "$out"
    runHook postInstall
  '';

  meta = with lib; {
    description = selected.description;
    homepage = "https://github.com/openai/codex";
    license = licenses.asl20;
    platforms = if runtime == "native" then
      [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ]
    else
      platforms.all;
    mainProgram = selected.binName;
  };
}
