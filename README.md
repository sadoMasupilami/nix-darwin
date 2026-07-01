# nix-darwin config

This repo manages:

- macOS system configuration via `nix-darwin`
- Home Manager on macOS
- a separate Linux Home Manager setup in [`home-manager/`](/Users/michaelklug/.config/nix-darwin/home-manager)

Machine-specific values are centralized in [`machine-config.nix`](/Users/michaelklug/.config/nix-darwin/machine-config.nix).

## First install on macOS

Install the prerequisites:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
sh -s -- install

softwareupdate --install-rosetta
```

Clone this repo to the expected path:

```bash
mkdir -p ~/.config
cd ~/.config
git clone https://github.com/sadomasupilami/nix-darwin.git
```

Adjust the machine-specific settings in:

```bash
~/.config/nix-darwin/machine-config.nix
```

This file is part of the flake, so it must stay tracked by Git.

Apply the macOS configuration:

```bash
cd ~/.config/nix-darwin
sudo darwin-rebuild switch --flake .#macos
```

## Updating on macOS

After the first successful activation, Home Manager installs two helper scripts:

```bash
nix-config-update
nix-config-apply
```

On macOS they currently do:

- `nix-config-update`: updates the main flake, Homebrew, casks, and App Store apps
- `nix-config-apply`: raises `ulimit -n`, runs `darwin-rebuild switch --flake <repo>#macos`, and collects garbage

## Linux Home Manager

Install Nix:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
sh -s -- install
```

Clone the repo:

```bash
mkdir -p ~/.config
cd ~/.config
git clone https://github.com/sadomasupilami/nix-darwin.git
```

Adjust the Linux values in:

```bash
~/.config/nix-darwin/machine-config.nix
```

Apply Home Manager:

```bash
~/.config/nix-darwin/home-manager/apply-home-manager.sh
```

After the first successful activation, the same helper names are installed for Linux:

- `nix-config-update`: updates the `home-manager/` flake
- `nix-config-apply`: runs `home-manager switch --flake .#default` from `home-manager/` and collects garbage

## Notes

- `machine-config.nix` is the single place for username, host name, home directories, and repo path.
- Homebrew is managed declaratively through `nix-homebrew` and the `homebrew` section in [`darwin.nix`](/Users/michaelklug/.config/nix-darwin/darwin.nix).
- Package search: https://search.nixos.org

## Manual

- Bartender license
