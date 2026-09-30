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
  version = "0.157.1";

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

  # Codex >= 0.157 starts its app-server daemon only from a package root, which
  # it finds by canonicalising its own executable. The daemon copies that root
  # into CODEX_HOME and runs it outside the store, so the root comes from
  # OpenAI's package archive, whose helpers do not depend on the store. On
  # Linux the codex binary also pins the digest of the bundled bwrap.
  packageHashes = {
    "aarch64-apple-darwin" = "1asax88kdsv69cikr9y7x3fakbqi42i9ldk5x7fdkx62366m7nkc";
    "x86_64-apple-darwin" = "0xxgss4syy4593nq8ds2liwp8dhfhw487c88wwilkxyiqxb5la6j";
    "x86_64-unknown-linux-musl" = "0pzyj2jmj34qvy9s9y1x8ngnppxgbrdngb1mmm4wnwzxr5l1h88f";
    "aarch64-unknown-linux-musl" = "0wdl8yx64libxkiafph7gaja3i7nxnqw2kjsd95r1r7lf06yg7s9";
  };

  nodeOptionalDepHashes = {
    "darwin-arm64" = "10xj8iik010jknrks1p735mvw31gsdx29hd1w6jckqg5y906c6f5";
    "darwin-x64" = "1300x5j3ryapqiq56fxfj51zwzxfcjq94q03ifgn331ryl06rckp";
    "linux-x64" = "1a32476bq6xxbaha77zaypn1qmryf2fis0y7hi4gwfgl81vnf4kz";
    "linux-arm64" = "0kw2w5q5i8rff2cl9yr2gj9mjcs737lidzp5xif9v9k314n4hgdp";
  };

  codexPackage = if runtime == "native" && platform != null then
    fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${platform}.tar.gz";
      sha256 = packageHashes.${platform};
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

  # The archive also carries zsh and voice helpers that this package has never
  # shipped; on Linux they too need a glibc loader that NixOS does not provide.
  packageFiles = [ "codex-package.json" "bin/codex" "bin/codex-code-mode-host" ]
    ++ lib.optionals (!useStaticRg) [ "codex-path/rg" ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ "codex-resources/bwrap" ];

  npmTarball = if runtime == "node" then
    fetchurl {
      url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz";
      sha256 = "0wsvizx53v5ycxq7lgzld06din3ad6zyi73dhbhvfx249ya2lgl1";
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
    tar -xzf ${codexPackage} -C build ${lib.escapeShellArgs packageFiles}
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
    mkdir -p $out/bin $out/libexec

    # Codex resolves its package root from the executable it is actually
    # running, so the binaries live in a package root rather than directly in
    # libexec. The wrapper below still supplies the environment: it execs the
    # real binary in place, which leaves the resolved path inside the root.
    # The code-mode host must remain next to the executable Codex actually runs.
    cp -R build $out/libexec/codex-package
    ${lib.optionalString useStaticRg ''
      mkdir -p $out/libexec/codex-package/codex-path
      tar -xzf ${staticRg} --strip-components=1 \
        -C $out/libexec/codex-package/codex-path ${staticRgName}/rg
      mkdir -p $out/share/licenses/ripgrep
      tar -xzf ${staticRg} --strip-components=1 \
        -C $out/share/licenses/ripgrep \
        ${staticRgName}/COPYING ${staticRgName}/LICENSE-MIT ${staticRgName}/UNLICENSE
    ''}

    ln -s ../libexec/codex-package/bin/codex-code-mode-host $out/bin/codex-code-mode-host
    makeWrapper "$out/libexec/codex-package/bin/codex" "$out/bin/${selected.binName}" \
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
