{
  # nix-locate, the zsh command-not-found hint and comma read the prebuilt
  # database from the nix-index-database input (imported in flake.nix), so it
  # moves with flake.lock and nothing indexes nixpkgs locally.
  programs = {
    nix-index.enable = true;
    # `, <command>` runs a command from nixpkgs without installing it.
    nix-index-database.comma.enable = true;
  };
}
