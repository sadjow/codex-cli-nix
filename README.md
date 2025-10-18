# codex-cli-nix

Always up-to-date Nix package for [OpenAI Codex](https://github.com/openai/codex) - lightweight AI coding agent in your terminal.

**🚀 Automatically updated hourly** to ensure you always have the latest Codex version.

## Why this package?

### Primary Goal: Always Up-to-Date Codex for Nix Users

This flake provides immediate access to the latest OpenAI Codex versions with:

1. **Hourly Automated Updates**: New Codex versions available within 1 hour of release
2. **Dedicated Maintenance**: Focused repository for quick fixes when Codex changes
3. **Flake-First Design**: Direct flake usage with Cachix binary cache
4. **Pre-built Binaries**: Multi-platform builds (Linux & macOS) cached for instant installation
5. **Node.js 22 LTS**: Latest long-term support version for better performance and security

### Why Not Just Use npm Global?

While `npm install -g @openai/codex` works, it has critical limitations:
- **Disappears on Node.js Switch**: When projects use different Node.js versions (via asdf/nvm), Codex becomes unavailable
- **Must Reinstall Per Version**: Need to install Codex separately for each Node.js version
- **Not Declarative**: Can't be managed in your Nix configuration
- **Not Reproducible**: Different Node.js versions can cause inconsistencies
- **Outside Nix**: Doesn't integrate with Nix's dependency management

**Example Problem**: You're working on a legacy project that uses Node.js 16 via asdf. When you switch to that project, your globally installed Codex (from Node.js 22) disappears from your PATH. This flake solves this by bundling Node.js with Codex.

### Comparison Table

| Feature | npm global | This Flake |
|---------|------------|------------|
| **Latest Version** | ✅ Always | ✅ Hourly checks |
| **Node.js Version** | ⚠️ Per Node install | ✅ Node.js 22 LTS |
| **Survives Node Switch** | ❌ Lost on switch | ✅ Always available |
| **Binary Cache** | ❌ None | ✅ Cachix |
| **Declarative Config** | ❌ None | ✅ Yes |
| **Version Pinning** | ⚠️ Manual | ✅ Flake lock |
| **Update Frequency** | ✅ Immediate | ✅ <= 1 hour |
| **Reproducible** | ❌ No | ✅ Yes |
| **CI/CD Ready** | ❌ No | ✅ Yes |

## Quick Start

### Fastest Installation (Try it now!)

```bash
# Run Codex directly without installing
nix run github:sadjow/codex-cli-nix
```

### Install to Your System

```bash
# Using nix profile (recommended for Nix 2.4+)
nix profile install github:sadjow/codex-cli-nix

# Or using nix-env (legacy)
nix-env -if github:sadjow/codex-cli-nix
```

### Optional: Enable Binary Cache for Faster Installation

To download pre-built binaries instead of compiling:

```bash
# Install cachix if you haven't already
nix-env -iA cachix -f https://cachix.org/api/v1/install

# Add the codex-cli cache
cachix use codex-cli
```

Or add to your Nix configuration:

```nix
{
  nix.settings = {
    substituters = [ "https://codex-cli.cachix.org" ];
    trusted-public-keys = [ "codex-cli.cachix.org-1:YOUR_PUBLIC_KEY_HERE" ];
  };
}
```

## Using with Nix Flakes

### In your flake.nix

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    codex-cli-nix.url = "github:sadjow/codex-cli-nix";
  };

  outputs = { self, nixpkgs, codex-cli-nix }:
    let
      system = "x86_64-linux"; # or your system
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          codex-cli-nix.packages.${system}.default
        ];
      };
    };
}
```

### Using with NixOS

Add to your system configuration:

```nix
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    inputs.codex-cli-nix.packages.${pkgs.system}.default
  ];
}
```

### Using with Home Manager

Add to your Home Manager configuration:

```nix
{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.codex-cli-nix.packages.${pkgs.system}.default
  ];
}
```

## Technical Details

### Package Architecture

Our custom `package.nix` implementation:

1. **Pre-fetches npm tarball**: Uses Nix's Fixed Output Derivation (FOD) for reproducible, offline builds
2. **Bundles Node.js 22 LTS**: Ensures consistent runtime environment across all systems
3. **Custom wrapper script**: Handles PATH, environment variables, and Codex-specific requirements
4. **Multi-platform builds**: CI builds and caches for both Linux and macOS
5. **Sandbox compatible**: All network fetching happens during the FOD phase, not build phase

### Runtime Environment

Currently using **Node.js 22 LTS** because:
- Long-term stability and support until April 2027
- Better performance than older Node.js versions
- Latest LTS with all security updates
- Consistent behavior across all platforms

### Features

- **Bundled Node.js Runtime**: Ships with Node.js v22 LTS for maximum compatibility
- **No Global Dependencies**: Works independently of system Node.js installations
- **Version Pinning**: Ensures consistent behavior across different environments
- **Offline Installation**: Pre-fetches npm packages for reliable builds
- **Auto-update Protection**: Prevents unexpected updates that might break your workflow
- **Cross-platform Support**: Pre-built binaries for Linux and macOS

## Development

```bash
# Clone the repository
git clone https://github.com/sadjow/codex-cli-nix
cd codex-cli-nix

# Build locally
nix build

# Test the build
./result/bin/codex --version

# Enter development shell
nix develop
```

## Updating Codex Version

### Automated Updates

This repository uses GitHub Actions to automatically check for new Codex versions hourly. When a new version is detected:

1. A pull request is automatically created with the version update
2. The tarball hash is automatically calculated
3. Tests run on both Linux and macOS to verify the build
4. The PR auto-merges if all checks pass

The automated update workflow runs:
- Every hour (on the hour) UTC
- On manual trigger via GitHub Actions UI

### Manual Updates

For manual updates:

1. Check for new versions:
   ```bash
   ./scripts/update.sh --check
   ```
2. Update to latest version:
   ```bash
   # Get the latest version number from the check above
   ./scripts/update.sh 0.30.0  # Replace with actual version
   ```
3. Test the build:
   ```bash
   nix build
   ./result/bin/codex --version
   ```

### Push to Cachix manually
```bash
nix build .#codex
cachix push codex-cli ./result
```

## Troubleshooting

### Command not found
Make sure the Nix profile bin directory is in your PATH:
```bash
export PATH="$HOME/.nix-profile/bin:$PATH"
```

### Permission issues on macOS

On macOS, Codex may ask for permissions after each Nix update because the binary path changes. To fix this:

1. Create a stable symlink: 
   ```bash
   mkdir -p ~/.local/bin
   ln -sf $(which codex) ~/.local/bin/codex
   ```
2. Add `~/.local/bin` to your PATH
3. Always run `codex` from `~/.local/bin/codex`

The wrapper script sets a consistent executable path to help prevent macOS permission resets.

### SSL certificate errors
The package automatically configures SSL certificates from the Nix store.

## Repository Settings

This repository requires specific GitHub settings for automated updates. See [Repository Settings Documentation](.github/REPOSITORY_SETTINGS.md) for configuration details.

## License

This Nix packaging is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

OpenAI Codex CLI itself is licensed under the Apache-2.0 License - see [OpenAI's repository](https://github.com/openai/codex) for details.

## Contributing

Contributions are welcome! Please submit pull requests or issues on GitHub.

## Related Projects

- [claude-code-nix](https://github.com/sadjow/claude-code-nix) - Similar packaging for Anthropic's Claude Code
- [nixpkgs](https://github.com/NixOS/nixpkgs) - The Nix Packages collection
