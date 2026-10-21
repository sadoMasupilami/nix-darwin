{
  description = "Michaels macOS and Linux configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Prebuilt nix-locate database, so nix-index never indexes nixpkgs locally.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sample mods for Claude Code, versioned alongside the rest of the environment.
    claude-code-playground = {
      url = "github:anthropics/claude-code-playground";
      flake = false;
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    # nix-homebrew owns these tap checkouts. Revisions live only in flake.lock
    # so `nix-config-update homebrew` can advance the complete source cohort.
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-azd = {
      url = "github:Azure/homebrew-azd";
      flake = false;
    };
    homebrew-silverstein-tap = {
      url = "github:silverstein/homebrew-tap";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      nix-index-database,
      nix-homebrew,
      determinate,
      ...
    }:
    let
      inherit (nixpkgs) lib;

      machineConfig = import ./machine-config.nix;
      inherit (machineConfig) username;

      darwinSystem = machineConfig.darwin.system;
      linuxSystem = machineConfig.linux.system;
      supportedSystems = [
        darwinSystem
        linuxSystem
      ];

      forAllSystems = lib.genAttrs supportedSystems;

      overlay = import ./overlays/kcat.nix;

      # One package set per system, shared by nix-darwin, Home Manager,
      # packages and checks. An attrset, not a function: Nix does not cache
      # function results, so each call would instantiate nixpkgs again.
      pkgsFor = forAllSystems (
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [ overlay ];
        }
      );
      darwinPkgs = pkgsFor.${darwinSystem};
      linuxPkgs = pkgsFor.${linuxSystem};

      # Home Manager modules for both platforms. home.nix imports the
      # repo-local ones; the platform-specific extras are added below.
      sharedHomeModules = [
        nix-index-database.homeModules.nix-index
        ./home.nix
      ];

      homeSpecialArgs = host: {
        inherit username;
        claudeModsSource = inputs.claude-code-playground;
        inherit (host) homeDirectory homeStateVersion repoDirectory;
      };

      # fetch-models.py imports huggingface_hub, so mypy needs it for the types.
      mkPythonEnv =
        pkgs:
        pkgs.python313.withPackages (p: [
          p.huggingface-hub
          p.mypy
        ]);

      mkFormatter =
        pkgs:
        pkgs.writeShellApplication {
          name = "nix-config-fmt";
          runtimeInputs = [
            pkgs.fd
            pkgs.nixfmt
          ];
          text = ''
            has_path=false
            for arg in "$@"; do
              case "$arg" in
                -*) ;;
                *) has_path=true ;;
              esac
            done

            if [ "$#" -gt 0 ] && [ "$has_path" = true ]; then
              exec nixfmt "$@"
            fi

            fd --extension nix --type f --exec-batch nixfmt "$@" {}
          '';
        };

      mkFormattingCheck =
        pkgs:
        pkgs.runCommand "nix-formatting"
          {
            nativeBuildInputs = [
              pkgs.findutils
              pkgs.nixfmt
            ];
            src = self;
          }
          ''
            cd "$src"
            find . -type f -name '*.nix' -print0 | xargs -0 nixfmt --check
            touch "$out"
          '';

      mkNixLint =
        pkgs:
        pkgs.runCommand "nix-lint"
          {
            nativeBuildInputs = [
              pkgs.deadnix
              pkgs.statix
            ];
            src = self;
          }
          ''
            cd "$src"
            statix check .
            deadnix --fail .
            touch "$out"
          '';

      mkPythonTypeCheck =
        pkgs:
        pkgs.runCommand "python-types"
          {
            nativeBuildInputs = [ (mkPythonEnv pkgs) ];
            src = self;
          }
          ''
            cd "$src"
            mypy --strict --cache-dir="$TMPDIR/mypy" \
              config/qwen-meeting/runtime/fetch-models.py tests/*.py
            touch "$out"
          '';

      # The same per-file rules as the pre-commit hook: .github/hooks/check-shell.sh
      # decides by shebang or file name, so everything else is skipped.
      mkShellCheck =
        pkgs:
        pkgs.runCommand "shell-lint"
          {
            nativeBuildInputs = [
              pkgs.findutils
              pkgs.shellcheck
              pkgs.zsh
            ];
            src = self;
          }
          ''
            cd "$src"
            find config tests .github/hooks -type f -print0 \
              | xargs -0 bash .github/hooks/check-shell.sh
            touch "$out"
          '';

      mkHelperTests =
        pkgs:
        pkgs.runCommand "nix-config-helper-tests"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.diffutils
              pkgs.findutils
              pkgs.gawk
              pkgs.git
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
            ];
            src = self;
          }
          ''
            cp -R "$src" source
            chmod -R +w source
            patchShebangs source/config source/tests
            cd source
            for test in nix-config-helpers nix-gc-recent glab-sync ssh-config-reconcile; do
              if [[ ! -f "tests/$test.sh" ]]; then
                echo "error: tests/$test.sh is missing" >&2
                exit 1
              fi
              echo "running tests/$test.sh"
              bash "./tests/$test.sh"
            done
            touch "$out"
          '';

      mkEvaluationCheck =
        pkgs:
        let
          # Reading drvPath forces full module evaluation. Discarding its store
          # context keeps the foreign-platform path an assertion value rather
          # than making it a dependency of this native check derivation.
          darwinDrvPath = builtins.unsafeDiscardStringContext darwinConfiguration.system.drvPath;
          linuxDrvPath = builtins.unsafeDiscardStringContext linuxHomeConfiguration.activationPackage.drvPath;
        in
        pkgs.runCommand "configuration-evaluation" { } ''
          test -n ${lib.escapeShellArg darwinDrvPath}
          test -n ${lib.escapeShellArg linuxDrvPath}
          touch "$out"
        '';

      mkLocalToolsCheck =
        pkgs:
        pkgs.runCommand "local-private-tools-tests"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.python313
              pkgs.uv
              pkgs.zsh
            ];
            src = self;
          }
          ''
            cp -R "$src" source
            chmod -R +w source
            patchShebangs source/config/qwen-meeting source/config/raycast source/tests
            cd source
            export UV_CACHE_DIR="$TMPDIR/uv-cache"
            bash ./tests/run-local-tools-tests.sh
            touch "$out"
          '';

      # Runs the usage-meter tests and validates both linked mods with the
      # nixpkgs Claude Code, so a claude-code-playground pin update is
      # validated too. Reviewing the new hooks stays a manual step. The test
      # runner needs the macOS ICU data in /usr/share/icu, so this check
      # requires an unsandboxed build, the Nix default on macOS.
      mkClaudeModsCheck =
        pkgs:
        pkgs.runCommand "claude-mods"
          {
            nativeBuildInputs = [ pkgs.claude-code ];
            usageMeter = ./config/claude-mods/usage-meter;
            tokenWeather = "${inputs.claude-code-playground}/claude-code/mods/token-weather";
          }
          ''
            # An empty HOME and no update check or telemetry: the check needs
            # neither an account nor the network.
            export HOME="$TMPDIR"
            export DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
            cp -R "$usageMeter" usage-meter
            chmod -R u+w usage-meter
            claude plugin test usage-meter
            claude plugin validate usage-meter
            claude plugin validate "$tokenWeather"
            touch "$out"
          '';

      linuxHomeConfiguration = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = sharedHomeModules ++ [
          ./modules/home-manager-base.nix
          ./modules/linux-gc.nix
        ];
        extraSpecialArgs = homeSpecialArgs machineConfig.linux;
      };

      darwinConfiguration = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit inputs username;
          inherit (machineConfig.darwin)
            homeDirectory
            hostName
            repoDirectory
            stateVersion
            ;
        };
        modules = [
          # nix-darwin and Home Manager (useGlobalPkgs) use the flake's
          # package set, overlays included.
          { nixpkgs.pkgs = darwinPkgs; }

          ./darwin.nix

          # Determinate manages /etc/nix/nix.conf and nix.custom.conf; the
          # settings live in modules/nix-settings.nix.
          determinate.darwinModules.default
          nix-homebrew.darwinModules.nix-homebrew

          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = homeSpecialArgs machineConfig.darwin;
              users.${username}.imports = sharedHomeModules ++ [
                ./modules/local-private-tools.nix
              ];
            };
          }
        ];
      };

      # Built in modules/homebrew.nix (packages/homebrew-preflight), whose
      # activation gate runs the same launcher as nix-config-preflight.
      homebrewPreflight = darwinConfiguration.config.system.build.homebrewPreflight;
    in
    {
      darwinConfigurations.macos = darwinConfiguration;

      # Keep both the historical `default` selector and the explicit username.
      homeConfigurations = {
        ${username} = linuxHomeConfiguration;
        default = linuxHomeConfiguration;
      };

      overlays.default = overlay;

      formatter = forAllSystems (system: mkFormatter pkgsFor.${system});

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor.${system};
        in
        {
          # Everything the checks and the local test commands call.
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.bash
              pkgs.deadnix
              pkgs.git
              pkgs.jq
              (mkPythonEnv pkgs)
              pkgs.nixfmt
              pkgs.pre-commit
              pkgs.shellcheck
              pkgs.statix
              pkgs.uv
              pkgs.zsh
            ];
          };
        }
      );

      apps = {
        ${darwinSystem} = {
          darwin-rebuild = {
            type = "app";
            program = "${nix-darwin.packages.${darwinSystem}.darwin-rebuild}/bin/darwin-rebuild";
            meta.description = "Run the nix-darwin CLI pinned by this flake";
          };
          home-manager = {
            type = "app";
            program = "${home-manager.packages.${darwinSystem}.home-manager}/bin/home-manager";
            meta.description = "Run the Home Manager CLI pinned by this flake";
          };
          default = self.apps.${darwinSystem}.darwin-rebuild;
        };
        ${linuxSystem} = {
          home-manager = {
            type = "app";
            program = "${home-manager.packages.${linuxSystem}.home-manager}/bin/home-manager";
            meta.description = "Run the Home Manager CLI pinned by this flake";
          };
          default = self.apps.${linuxSystem}.home-manager;
        };
      };

      packages.${darwinSystem} = {
        homebrew-preflight = homebrewPreflight;
        qwen-meeting-runtime = darwinPkgs.callPackage ./packages/qwen-meeting-runtime { };
      };

      checks = {
        ${darwinSystem} = {
          darwin = darwinConfiguration.system;
          claude-mods = mkClaudeModsCheck darwinPkgs;
          evaluation = mkEvaluationCheck darwinPkgs;
          formatting = mkFormattingCheck darwinPkgs;
          homebrew-preflight = homebrewPreflight;
          local-private-tools = mkLocalToolsCheck darwinPkgs;
          qwen-meeting-runtime = self.packages.${darwinSystem}.qwen-meeting-runtime;
          nix-config-helpers = mkHelperTests darwinPkgs;
          nix-lint = mkNixLint darwinPkgs;
          python-types = mkPythonTypeCheck darwinPkgs;
          shell = mkShellCheck darwinPkgs;
        };
        ${linuxSystem} = {
          evaluation = mkEvaluationCheck linuxPkgs;
          linux-home-manager = linuxHomeConfiguration.activationPackage;
          formatting = mkFormattingCheck linuxPkgs;
          nix-config-helpers = mkHelperTests linuxPkgs;
          nix-lint = mkNixLint linuxPkgs;
          python-types = mkPythonTypeCheck linuxPkgs;
          shell = mkShellCheck linuxPkgs;
        };
      };
    };
}
