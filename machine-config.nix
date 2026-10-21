{
  username = "michaelklug";

  # State versions keep the defaults of each machine's first activation. They
  # belong to the machine, not to the shared configuration: never bump them
  # for an existing host, and give a new host the then-current release.
  darwin = {
    system = "aarch64-darwin";
    hostName = "fs-macbook-pro-m4";
    homeDirectory = "/Users/michaelklug";
    repoDirectory = "/Users/michaelklug/.config/nix-darwin";
    stateVersion = 5;
    homeStateVersion = "23.11";
  };

  linux = {
    system = "x86_64-linux";
    homeDirectory = "/home/michaelklug";
    repoDirectory = "/home/michaelklug/.config/nix-darwin";
    homeStateVersion = "23.11";
  };
}
