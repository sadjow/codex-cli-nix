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
, zstd
, openssl
, libcap
, libz
, bubblewrap
, runtime ? "native"
, nativeBinName ? "codex"
, nodeBinName ? "codex-node"
}:

let
  version = "0.163.0";

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

  # Daemon bootstrap copies this complete package, including its manifest.
  nativeHashes = {
    "aarch64-apple-darwin" = "0b20ndp3g8lg38bga5v5r80ns764icg6165zx81k0phiavljx084";
    "x86_64-apple-darwin" = "0f3yva2myxxhzw4wkn025lznw4921ma8ki8lr074q308ysigrxjz";
    "x86_64-unknown-linux-musl" = "15lwrxj99m5bgwj58xdsd9cal75ygw317cg82zl2fyabyb0xl8nz";
    "aarch64-unknown-linux-musl" = "1sb0haqzbw04rm80bwr349ip8gvgvbdifp3biyyxzdf4lh0vk57v";
  };

  nodeOptionalDepHashes = {
    "darwin-arm64" = "0c9wrpx28nbinjnfhn59cxy00zf5km5ba828qgbab1r3wx6gz4qi";
    "darwin-x64" = "1nphmdmmpawd41i82hg1pqxpnsn5l81v11gwpsgh598qg9xps9kl";
    "linux-x64" = "156y51snpbimxia7v01jnx0418sz27m9p6mmg06r8xdr71vwkvrh";
    "linux-arm64" = "08imfs24nf5db06n68kgnwazdvppgxby418dysh26777dm6pqvnw";
  };

  nativeBinaryUrl = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${platform}.tar.zst";

  nativeBinary = if runtime == "native" && platform != null then
    fetchurl {
      url = nativeBinaryUrl;
      sha256 = nativeHashes.${platform};
    }
  else null;

  # The bundled ARM64 Linux rg requires a glibc loader. Use a static archive
  # so the daemon's copied package also survives Nix store garbage collection.
  useStaticRg = stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64;
  staticRgVersion = "15.2.0";
  staticRgName = "ripgrep-${staticRgVersion}-aarch64-unknown-linux-musl";
  staticRg = fetchurl {
    url = "https://github.com/BurntSushi/ripgrep/releases/download/${staticRgVersion}/${staticRgName}.tar.gz";
    sha256 = "0589fkhqc7pn020m6412wphapykw2hiiz456npgrkrxg0rr1w2w0";
  };

  npmTarball = if runtime == "node" then
    fetchurl {
      url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz";
      sha256 = "1d2mclz5vcniz0rsb373mhw8q0d3qisycfp6qb94dd0baqvdnw8s";
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
      nativeBuildInputs = [ gnutar gzip zstd makeWrapper ];
      buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ openssl libcap libz ];
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
  linuxRuntimePath = lib.makeBinPath (lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap ]);
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
    tar --zstd -xf ${nativeBinary} -C build

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
    mkdir -p $out/bin $out/lib

    # Codex discovers its package from bin/ and the adjacent manifest.
    cp -r build $out/lib/codex
    ${lib.optionalString useStaticRg ''
      rm $out/lib/codex/codex-path/rg
      tar -xzf ${staticRg} --strip-components=1 \
        -C $out/lib/codex/codex-path ${staticRgName}/rg
      mkdir -p $out/share/licenses/ripgrep
      tar -xzf ${staticRg} --strip-components=1 \
        -C $out/share/licenses/ripgrep \
        ${staticRgName}/COPYING ${staticRgName}/LICENSE-MIT ${staticRgName}/UNLICENSE
    ''}

    ln -s ../lib/codex/bin/codex-code-mode-host $out/bin/codex-code-mode-host
    makeWrapper "$out/lib/codex/bin/codex" "$out/bin/${selected.binName}" \
      --run 'export CODEX_EXECUTABLE_PATH="$HOME/.local/bin/${selected.binName}"' \
      --set DISABLE_AUTOUPDATER 1 \
      ${lib.optionalString stdenv.hostPlatform.isLinux ''--prefix PATH : "${linuxRuntimePath}"''}
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
      ${lib.optionalString stdenv.hostPlatform.isLinux ''--prefix PATH : "${linuxRuntimePath}"''}
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
