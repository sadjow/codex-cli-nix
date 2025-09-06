# codex-nix

A Nix flake for [OpenAI Codex](https://github.com/openai/codex).

This flake packages Codex with its own Node.js runtime, ensuring consistent availability regardless of project-specific Node.js versions.

## Quick Start

### Using Binary Cache (Recommended)

Enable the Cachix binary cache to get pre-built binaries:

```bash
# Install cachix if you haven't already
nix-env -iA cachix -f https://cachix.org/api/v1/install

# Add the codex-cli cache
cachix use codex-cli
```

### Try without installing
```bash
nix run github:yourusername/codex-nix
```

### Install globally
```bash
# Add to your system or home-manager configuration
nix profile install github:yourusername/codex-nix

# Or use nix-env
nix-env -iA codex -f github:yourusername/codex-nix
```

### Use in development shell
```nix
# In your flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    codex-nix.url = "github:yourusername/codex-nix";
  };

  outputs = { self, nixpkgs, codex-nix }:
    let
      system = "x86_64-linux"; # or your system
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          codex-nix.packages.${system}.default
        ];
      };
    };
}
```

## Features

- **Bundled Node.js Runtime**: Ships with Node.js v22 LTS for maximum compatibility
- **No Global Dependencies**: Works independently of system Node.js installations
- **Version Pinning**: Ensures consistent behavior across different environments
- **Offline Installation**: Pre-fetches npm packages for reliable builds
- **Auto-update Protection**: Prevents unexpected updates that might break your workflow

## Configuration

### Using with NixOS

Add to your system configuration:

```nix
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    inputs.codex-nix.packages.${pkgs.system}.default
  ];
}
```

### Using with Home Manager

Add to your Home Manager configuration:

```nix
{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.codex-nix.packages.${pkgs.system}.default
  ];
}
```

## Development

### Setup Cachix Authentication

To push builds to Cachix, you'll need to:

1. Get your auth token from [Cachix](https://app.cachix.org/cache/codex-cli#pull)
2. Add it as a GitHub secret named `CACHIX_AUTH_TOKEN` in your repository settings

### Build locally
```bash
nix build
```

### Enter development shell
```bash
nix develop
```

### Update to new version
1. Edit `version` in `package.nix`
2. Update the SHA256 hash:
   ```bash
   nix-prefetch-url https://registry.npmjs.org/@openai/codex/-/codex-VERSION.tgz
   ```
3. Replace the hash in `package.nix`
4. Test the build:
   ```bash
   nix build
   ```

### Push to Cachix manually
```bash
nix build
cachix push codex-cli ./result
```

## Troubleshooting

### Command not found
Make sure the Nix profile bin directory is in your PATH:
```bash
export PATH="$HOME/.nix-profile/bin:$PATH"
```

### Permission issues on macOS
The wrapper script sets a consistent executable path to prevent macOS permission resets.

### SSL certificate errors
The package automatically configures SSL certificates from the Nix store.

## License

This Nix packaging is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

OpenAI Codex CLI itself is licensed under the Apache-2.0 License - see [OpenAI's repository](https://github.com/openai/codex) for details.

## Contributing

Contributions are welcome! Please submit pull requests or issues on GitHub.

## Related Projects

- [claude-code-nix](https://github.com/sadjow/claude-code-nix) - Similar packaging for Anthropic's Claude Code
- [nixpkgs](https://github.com/NixOS/nixpkgs) - The Nix Packages collection