{ lib
, buildNpmPackage
, fetchFromGitHub
, nodejs_22
}:

buildNpmPackage rec {
  pname = "codex-cli";
  version = "0.29.0";

  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = "rust-v${version}";
    sha256 = "sha256-YCQfycmDPRxMAqo57tt/6IXkUn1JIPTzEHMNbt7m3w0=";
  };

  npmDepsHash = "sha256-mUx1zhX96OtEr7d1t0IXieUaoR6U+/PCnFtI958U47o=";

  nodejs = nodejs_22;
  
  makeCacheWritable = true;
  
  # The npm package is in the codex-cli subdirectory
  sourceRoot = "source/codex-cli";
  
  # Don't build, just install
  dontNpmBuild = true;

  meta = with lib; {
    description = "OpenAI Codex CLI - AI coding assistant in your terminal";
    homepage = "https://github.com/openai/codex";
    license = licenses.unfree;
    platforms = platforms.all;
    mainProgram = "codex";
  };
}