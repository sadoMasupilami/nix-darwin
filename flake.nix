{
  description = "Michaels macOS and Linux configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
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
      nix-homebrew,
      determinate,
      ...
    }:
    let
      machineConfig = import ./machine-config.nix;
      inherit (machineConfig) username;

      nixHomebrewLock = builtins.fromJSON (builtins.readFile (inputs.nix-homebrew + "/flake.lock"));
      homebrewVersion = nixHomebrewLock.nodes."brew-src".original.ref;

      darwinSystem = machineConfig.darwin.system;
      linuxSystem = machineConfig.linux.system;
      supportedSystems = [
        darwinSystem
        linuxSystem
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

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

      mkShellCheck =
        pkgs:
        pkgs.runCommand "shell-syntax"
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

            while IFS= read -r -d $'\0' script; do
              case "$(head -n 1 "$script")" in
                *bash*) shellcheck --severity=error "$script" ;;
                *zsh*) zsh -n "$script" ;;
              esac
            done < <(find config tests -type f -print0)

            touch "$out"
          '';

      mkHelperTests =
        pkgs:
        pkgs.runCommand "nix-config-helper-tests"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.gnugrep
            ];
            src = self;
          }
          ''
            cp -R "$src" source
            chmod -R +w source
            patchShebangs source/config/nix-config source/tests
            cd source
            ./tests/nix-config-helpers.sh
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
          test -n ${nixpkgs.lib.escapeShellArg darwinDrvPath}
          test -n ${nixpkgs.lib.escapeShellArg linuxDrvPath}
          touch "$out"
        '';

      mkLocalToolsCheck =
        pkgs:
        pkgs.runCommand "local-private-tools-tests"
          {
            nativeBuildInputs = [
              pkgs.bash
              pkgs.bats
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

      # Build an isolated launcher from the exact nix-homebrew activation
      # assets. It reads the current /opt/homebrew inventory, but runs the
      # locked Homebrew code and taps with disposable config/cache state. This
      # breaks the first-apply deadlock when the live Brew is too old to parse
      # the newly locked core tap.
      mkHomebrewPreflight =
        pkgs:
        let
          activation = pkgs.writeText "nix-homebrew-activation" ''
            ${darwinConfiguration.config.system.activationScripts.setup-homebrew.text}
            # Evaluation identity: ${self.dirtyRev or self.rev or "uncommitted"}
          '';
        in
        pkgs.runCommandLocal "homebrew-preflight"
          {
            inherit activation;
            wrapperTemplate = ./config/nix-config/homebrew-preflight-wrapper.sh.in;
          }
          ''
            setup_script=$(grep -Eo '/nix/store/[a-z0-9]{32}-setup-homebrew' "$activation" | head -n 1)
            test -n "$setup_script"
            test -x "$setup_script"

            brew_code=$(sed -n 's|^[[:space:]]*/bin/ln -shf "\([^"]*\)" "\$HOMEBREW_LIBRARY/Homebrew"$|\1|p' "$setup_script")
            taps=$(sed -n 's|^[[:space:]]*/bin/ln -shf "\([^"]*\)" "\$HOMEBREW_LIBRARY/Taps"$|\1|p' "$setup_script")
            prefix_wrapper=$(sed -n 's|^[[:space:]]*/bin/ln -shf "\([^"]*\)" "\$BIN_BREW"$|\1|p' "$setup_script")

            for value in "$brew_code" "$taps" "$prefix_wrapper"; do
              test -n "$value"
              test "$(printf '%s' "$value" | wc -l | tr -d ' ')" = 0
              case "$value" in
                /nix/store/*) ;;
                *) exit 1 ;;
              esac
            done
            test -f "$brew_code/brew.sh"
            test -d "$taps"
            test -x "$prefix_wrapper"

            # The copy is scoped to the preflight package and never replaces
            # the Homebrew code that nix-homebrew activates on the system.
            preflight_brew="$out/share/nix-homebrew-preflight/Homebrew"

            mkdir -p "$out/bin" "$out/libexec" "$out/share/nix-homebrew-preflight"
            cp -R "$brew_code" "$preflight_brew"
            chmod -R u+w "$preflight_brew"

            # Under no-install-from-API mode the pinned Core/Cask paths already
            # appear in `installed`; using the generic Tap instances avoids a
            # Homebrew 6 singleton edge case while preserving their contents.
            substituteInPlace "$preflight_brew/tap.rb" \
              --replace-fail \
                'return CoreTap.instance if ["Homebrew", "Linuxbrew"].include?(user) && ["core", "homebrew"].include?(repository)' \
                'return CoreTap.instance if !Homebrew::EnvConfig.no_install_from_api? && ["Homebrew", "Linuxbrew"].include?(user) && ["core", "homebrew"].include?(repository)' \
              --replace-fail \
                'return CoreCaskTap.instance if user == "Homebrew" && repository == "cask"' \
                'return CoreCaskTap.instance if !Homebrew::EnvConfig.no_install_from_api? && user == "Homebrew" && repository == "cask"' \
              --replace-fail \
                'HOMEBREW_TAP_DIRECTORY.subdirs.flat_map(&:subdirs).map { from_path(it) }' \
                'HOMEBREW_TAP_DIRECTORY.subdirs.flat_map(&:subdirs).filter_map { from_path(it) }'

            cp "$prefix_wrapper" "$out/libexec/brew"
            chmod u+w "$out/libexec/brew"

            old_brew_file_line=$(grep '^export HOMEBREW_BREW_FILE=' "$out/libexec/brew")
            test -n "$old_brew_file_line"
            substituteInPlace "$out/libexec/brew" \
              --replace-fail 'export HOMEBREW_LIBRARY="/opt/homebrew/Library"' \
                'export HOMEBREW_LIBRARY="''${NIX_HOMEBREW_PREFLIGHT_LIBRARY:?}"' \
              --replace-fail "$old_brew_file_line" \
                "export HOMEBREW_BREW_FILE=\"$out/bin/brew\"" \
              --replace-fail '  HOMEBREW_BREW_FILE' \
                '  HOMEBREW_BREW_FILE HOMEBREW_CACHE HOMEBREW_LOGS HOMEBREW_TEMP HOMEBREW_NO_ANALYTICS HOMEBREW_NO_AUTO_UPDATE HOMEBREW_NO_ENV_HINTS HOMEBREW_NO_INSTALL_FROM_API HOMEBREW_NO_REQUIRE_TAP_TRUST HOMEBREW_VERSION MAS_NO_AUTO_INDEX'

            substitute "$wrapperTemplate" "$out/bin/brew" \
              --replace-fail '@brewCode@' "$preflight_brew" \
              --replace-fail '@brewVersion@' ${nixpkgs.lib.escapeShellArg homebrewVersion} \
              --replace-fail '@taps@' "$taps" \
              --replace-fail '@innerWrapper@' "$out/libexec/brew"
            chmod 0555 "$out/bin/brew" "$out/libexec/brew"

            printf '%s\n' "$preflight_brew" > "$out/share/nix-homebrew-preflight/brew-code"
            printf '%s\n' "$taps" > "$out/share/nix-homebrew-preflight/taps"
          '';

      linuxPkgs = pkgsFor linuxSystem;
      linuxHomeDirectory = machineConfig.linux.homeDirectory;
      linuxRepoDirectory = machineConfig.linux.repoDirectory;

      linuxHomeConfiguration = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [
          ./modules/home-manager-base.nix
          ./home.nix
          ./modules/local-private-tools.nix
          ./modules/nix-config-helpers.nix
        ];
        extraSpecialArgs = {
          inherit username;
          homeDirectory = linuxHomeDirectory;
          repoDirectory = linuxRepoDirectory;
        };
      };

      darwinConfiguration = nix-darwin.lib.darwinSystem {
        system = darwinSystem;
        specialArgs = {
          inherit
            inputs
            self
            username
            darwinSystem
            ;
          inherit (machineConfig.darwin)
            homeDirectory
            hostName
            repoDirectory
            ;
        };
        modules = [
          ./darwin.nix

          # Determinate manages /etc/nix/nix.conf and nix.custom.conf.
          determinate.darwinModules.default
          {
            determinateNix = {
              enable = true;
              customSettings = {
                # Preserve the existing trusted local-development behavior.
                sandbox = false;
                trusted-users = [
                  "root"
                  username
                ];
                substituters = "https://cache.nixos.org https://devenv.cachix.org https://nixpkgs-unfree.cachix.org";
                trusted-substituters = "https://cache.nixos.org https://devenv.cachix.org https://nixpkgs-unfree.cachix.org";
                trusted-public-keys = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw= nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs=";
              };
            };
          }

          nix-homebrew.darwinModules.nix-homebrew
          {
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];

            # The non-flake brew-src input has no `version` attribute by
            # default, so nix-homebrew cannot embed the locked tag into its
            # patched source unless we add it explicitly.
            nix-homebrew.package = inputs.nix-homebrew.inputs.brew-src // {
              name = "brew-${homebrewVersion}";
              version = homebrewVersion;
            };
          }

          home-manager.darwinModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                inherit username;
                inherit (machineConfig.darwin)
                  homeDirectory
                  hostName
                  repoDirectory
                  ;
              };
              sharedModules = [
                ./modules/home-manager-base.nix
                ./modules/local-private-tools.nix
                ./modules/nix-config-helpers.nix
              ];
              users.${username} = import ./home.nix;
            };
          }
        ];
      };

      homebrewPreflight = mkHomebrewPreflight (pkgsFor darwinSystem);
    in
    {
      darwinConfigurations.macos = darwinConfiguration;

      # Keep both the historical `default` selector and the explicit username.
      homeConfigurations = {
        ${username} = linuxHomeConfiguration;
        default = linuxHomeConfiguration;
      };

      formatter = forAllSystems (system: mkFormatter (pkgsFor system));

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.nixfmt
              pkgs.shellcheck
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

      packages.${darwinSystem}.homebrew-preflight = homebrewPreflight;

      checks = {
        ${darwinSystem} = {
          darwin = darwinConfiguration.system;
          evaluation = mkEvaluationCheck (pkgsFor darwinSystem);
          formatting = mkFormattingCheck (pkgsFor darwinSystem);
          homebrew-preflight = homebrewPreflight;
          local-private-tools = mkLocalToolsCheck (pkgsFor darwinSystem);
          nix-config-helpers = mkHelperTests (pkgsFor darwinSystem);
          shell = mkShellCheck (pkgsFor darwinSystem);
        };
        ${linuxSystem} = {
          evaluation = mkEvaluationCheck linuxPkgs;
          linux-home-manager = linuxHomeConfiguration.activationPackage;
          formatting = mkFormattingCheck linuxPkgs;
          nix-config-helpers = mkHelperTests linuxPkgs;
          shell = mkShellCheck linuxPkgs;
        };
      };
    };
}
