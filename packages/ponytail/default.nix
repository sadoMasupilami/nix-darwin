{
  lib,
  stdenvNoCC,
  nodejs,
  python3,
  runCommand,
  src,
}:
let
  upstreamVersion = "4.9.0";
  # Node.js and the patch shape the installed hooks, so both name the build.
  # A nixpkgs bump that leaves Node.js untouched keeps the version and with it
  # the Codex plugin cache path and hook approval.
  buildIdentity = builtins.hashString "sha256" (
    lib.concatStringsSep ":" [
      src.rev
      (builtins.unsafeDiscardStringContext nodejs.outPath)
      (builtins.readFile ../../config/ponytail/patch-hooks.py)
      (builtins.readFile ./default.nix)
    ]
  );
  # The activation merges client settings with tomlkit; its tests share it.
  reconcilePython = python3.withPackages (p: [ p.tomlkit ]);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ponytail";
  version = "${upstreamVersion}-nix-${builtins.substring 0 16 buildIdentity}";
  inherit src;
  nativeBuildInputs = [ python3 ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R . "$out/"
    chmod -R u+w "$out"
    python3 ${../../config/ponytail/patch-hooks.py} "$out" ${nodejs}/bin/node \
      ${upstreamVersion} ${finalAttrs.version}
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    python3 ${../../tests/ponytail-runtime.py} "$out" ${finalAttrs.version}
    runHook postInstallCheck
  '';
  passthru = {
    inherit reconcilePython;
    tests.activation = runCommand "ponytail-activation-tests" { src = ../..; } ''
      cd "$src"
      ${reconcilePython}/bin/python3 -B tests/test_ponytail.py
      touch "$out"
    '';
  };
  meta = {
    description = "Ponytail agent plugin with a Nix-pinned hook runtime";
    homepage = "https://github.com/DietrichGebert/ponytail";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
