# initial install
## first install stuff to get started
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
sh -s -- install

softwareupdate --install-rosetta
```

## clone the repo
the path has to be exactly this one

```bash
mkdir -p ~/.config/
cd ~/.config/
git clone https://github.com/LnL7/nix-darwin.git
```

## apply the configuration
```bash
nix run nix-darwin -- switch --flake ~/.config/nix-darwin#macos
```

# updating in the future
we have installed 2 binaries which you can use in the future to get the newest versions and install them
```bash
nix-config-update
nix-config-apply
```

# where to find packages?
https://search.nixos.org

# install your configuration on linux
```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
sh -s -- install```
mkdir -p ~/.config/
cd ~/.config/
git clone https://github.com/LnL7/nix-darwin.git
~/.config/nix-darwin/home-manager/apply-home-manager.sh
```

# manual stuff for me
- 
