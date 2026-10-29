# An isolated launcher built from the exact nix-homebrew activation assets.
# It reads the current /opt/homebrew inventory, but runs the locked Homebrew
# code and taps with disposable config/cache state. This breaks the
# first-apply deadlock when the live Brew is too old to parse the newly
# locked core tap. nix-config-preflight previews the cleanup with it, and
# the activation's cleanup gate in modules/homebrew.nix runs the same one.
{
  lib,
  runCommandLocal,
  writeText,
  # nix-homebrew's setup-homebrew activation script, which names the assets.
  setupHomebrewText,
  # nix-homebrew labels its package with the brew-src tag from its own
  # flake.lock; nix-config-preflight compares `brew --version` to it.
  brewVersion,
  # The tap trust entries that nix-homebrew persists on activation.
  trustedTaps,
}:
runCommandLocal "homebrew-preflight"
  {
    activation = writeText "nix-homebrew-activation" ''
      ${setupHomebrewText}
    '';
    wrapperTemplate = ../../config/nix-config/homebrew-preflight-wrapper.sh.in;
    trustStore = writeText "homebrew-preflight-trust.json" (
      builtins.toJSON { trustedtaps = trustedTaps; }
    );
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
        '.map { from_path(it) }' \
        '.filter_map { from_path(it) }'

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
        '  HOMEBREW_BREW_FILE HOMEBREW_CACHE HOMEBREW_LOGS HOMEBREW_TEMP HOMEBREW_NO_ANALYTICS HOMEBREW_NO_AUTO_UPDATE HOMEBREW_NO_ENV_HINTS HOMEBREW_NO_INSTALL_FROM_API HOMEBREW_VERSION MAS_NO_AUTO_INDEX HOMEBREW_DEV_CMD_RUN'

    substitute "$wrapperTemplate" "$out/bin/brew" \
      --replace-fail '@brewCode@' "$preflight_brew" \
      --replace-fail '@brewVersion@' ${lib.escapeShellArg brewVersion} \
      --replace-fail '@taps@' "$taps" \
      --replace-fail '@trustStore@' "$trustStore" \
      --replace-fail '@innerWrapper@' "$out/libexec/brew"
    chmod 0555 "$out/bin/brew" "$out/libexec/brew"

    printf '%s\n' "$preflight_brew" > "$out/share/nix-homebrew-preflight/brew-code"
    printf '%s\n' "$taps" > "$out/share/nix-homebrew-preflight/taps"
  ''
