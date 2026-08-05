{ lib
, stdenv
, fetchurl
, nodejs_22
, cacert
, makeWrapper
, installShellFiles
, installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform
, gnutar
, gzip
, openssl
, libcap
, libz
, bubblewrap
, runtime ? "native"
, nativeBinName ? "codex"
, nodeBinName ? "codex-node"
}:

let
  version = "0.146.1";

  platformMap = {
    "aarch64-darwin" = "aarch64-apple-darwin";
    "x86_64-darwin" = "x86_64-apple-darwin";
    "x86_64-linux" = "x86_64-unknown-linux-musl";
    "aarch64-linux" = "aarch64-unknown-linux-musl";
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
    "aarch64-apple-darwin" = "088qg2yqsrwqph33298axfqn891cnr6q3mvaqibdajyjf2r5wz1k";
    "x86_64-apple-darwin" = "0l0z5x6kymgxcq6lkdawzp03ph2i6b033rflzqb5ynar4v16wpwp";
    "x86_64-unknown-linux-musl" = "1b14312rpfjgic5xdkiaqcfv9y49q3gklybh6nrnzgqjxid10n7m";
    "aarch64-unknown-linux-musl" = "0hsdwczvk0zx52yn2hlff6a6gv6m84wk3k10www21l3bggp6bph5";
  };

  # codex >= 0.143 spawns a separate `codex-code-mode-host` binary (found
  # next to the running executable) when "code mode" is enabled. Shipped as its
  # own release asset, so the native build must fetch and install it too.
  codeModeHostHashes = {
    "aarch64-apple-darwin" = "0px9jqazhim6c7qp89gjrmfd3zbd6h614gzjd4m8ah57ppiqqkzf";
    "x86_64-apple-darwin" = "0pirca8lq5fnz4nf0bgpc2s9q5xk3yffrdbccwmf2fwbfi5q0bfp";
    "x86_64-unknown-linux-musl" = "0928ajjrbknvmskndnh6m93k0p8ygn2jc8g5910bmd2381c8rkv0";
    "aarch64-unknown-linux-musl" = "0faj867830hxx8fpfngf65dncmm8sazzir4j2s6iamxcqab2v6ij";
  };

  nodeOptionalDepHashes = {
    "darwin-arm64" = "1z03mlinbv7vd9k1lryj04xd94pyqj6m7p4skcxy71hbq6shjibr";
    "darwin-x64" = "00zaw0a5mj8ng71qgiq94bqnxs4ixrqfqhxcxgjbh2mmbxwzqq7a";
    "linux-x64" = "0scsnk1w3z8m883p0lj59bq57l37kb39szfqnvqhvzbyh4s2dd6s";
    "linux-arm64" = "04268ga408c3ks9bapd500zy7mig41d514ygnrqfzshp5klnzfcm";
  };

  nativeBinaryUrl = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${platform}.tar.gz";

  nativeBinary = if runtime == "native" && platform != null then
    fetchurl {
      url = nativeBinaryUrl;
      sha256 = nativeHashes.${platform};
    }
  else null;

  codeModeHost = if runtime == "native" && platform != null then
    fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-code-mode-host-${platform}.tar.gz";
      sha256 = codeModeHostHashes.${platform};
    }
  else null;

  npmTarball = if runtime == "node" then
    fetchurl {
      url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz";
      sha256 = "1j7g79xh0zgyh9dsacxpayl73gwg8cpl1rm9dz02ym1d3709mal3";
    }
  else null;

  nodeOptionalDep = if runtime == "node" && nodePlatform != null then
    fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-npm-${nodePlatform}-${version}.tgz";
      sha256 = nodeOptionalDepHashes.${nodePlatform};
    }
  else null;

  runtimeConfig = {
    native = {
      nativeBuildInputs = [ gnutar gzip makeWrapper ];
      buildInputs = lib.optionals stdenv.isLinux [ openssl libcap libz ];
      description = "OpenAI Codex CLI (Native Binary) - AI coding assistant in your terminal";
      binName = nativeBinName;
    };
    node = {
      nativeBuildInputs = [ nodejs_22 cacert makeWrapper ];
      buildInputs = [];
      description = "OpenAI Codex CLI (Node.js) - AI coding assistant in your terminal";
      binName = nodeBinName;
    };
  };

  selected = runtimeConfig.${runtime};
  linuxRuntimePath = lib.makeBinPath (lib.optionals stdenv.isLinux [ bubblewrap ]);
  generateShellCompletions =
    installShellCompletions
    && runtime == "native"
    && selected.binName == "codex";
in
assert runtime == "native" -> platform != null ||
  throw "Native runtime not supported on ${stdenv.hostPlatform.system}. Supported: aarch64-darwin, x86_64-darwin, x86_64-linux, aarch64-linux";

stdenv.mkDerivation rec {
  pname = if runtime == "native" then "codex" else "codex-${runtime}";
  inherit version;

  dontUnpack = true;

  dontPatchELF = runtime == "native";
  dontStrip = runtime == "native";

  nativeBuildInputs = selected.nativeBuildInputs
    ++ lib.optionals generateShellCompletions [ installShellFiles ];
  buildInputs = selected.buildInputs;

  buildPhase = if runtime == "native" then ''
    runHook preBuild
    mkdir -p build
    tar -xzf ${nativeBinary} -C build
    mv build/codex-${platform} build/codex
    chmod u+w,+x build/codex

    tar -xzf ${codeModeHost} -C build
    mv build/codex-code-mode-host-${platform} build/codex-code-mode-host
    chmod u+w,+x build/codex-code-mode-host

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
    cp build/codex-code-mode-host $out/bin/codex-code-mode-host
    chmod +x $out/bin/codex-code-mode-host
    makeWrapper "$out/bin/codex-raw" "$out/bin/${selected.binName}" \
      --run 'export CODEX_EXECUTABLE_PATH="$HOME/.local/bin/${selected.binName}"' \
      --set DISABLE_AUTOUPDATER 1 \
      ${lib.optionalString stdenv.isLinux ''--prefix PATH : "${linuxRuntimePath}"''}
    runHook postInstall
  '' else ''
    runHook preInstall
    mkdir -p $out/bin

    makeWrapper ${nodejs_22}/bin/node "$out/bin/${selected.binName}" \
      --add-flags --no-warnings \
      --add-flags "$out/lib/node_modules/@openai/codex/bin/codex.js" \
      --set NODE_PATH "$out/lib/node_modules" \
      --run 'export CODEX_EXECUTABLE_PATH="$HOME/.local/bin/${selected.binName}"' \
      --set DISABLE_AUTOUPDATER 1 \
      ${lib.optionalString stdenv.isLinux ''--prefix PATH : "${linuxRuntimePath}"''}
    runHook postInstall
  '';

  postInstall = lib.optionalString generateShellCompletions ''
    installShellCompletion --cmd codex \
      --bash <("$out/bin/${selected.binName}" completion bash) \
      --fish <("$out/bin/${selected.binName}" completion fish) \
      --zsh <("$out/bin/${selected.binName}" completion zsh)
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
