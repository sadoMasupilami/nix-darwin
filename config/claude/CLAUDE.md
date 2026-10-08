# Environment

This machine uses Nix (nix-darwin). If a tool you need is not installed, don't install it globally (no `brew install`, `npm -g`, `pip install --user`, etc.). Run it through `nix shell` instead, for example:

```bash
nix shell nixpkgs#jq -c jq --version
```

Use `nix shell nixpkgs#<pkg1> nixpkgs#<pkg2>` when you need several tools at once.
