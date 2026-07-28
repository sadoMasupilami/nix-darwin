{
  cmake,
  fetchFromGitHub,
  lib,
  onnxruntime,
  pkg-config,
  rustPlatform,
  swift,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "minutes";
  version = "0.24.0";

  # Pin the release commit, not the movable tag. The additional `vad-ort`
  # feature is intentionally enabled because the recording sidecar otherwise
  # falls back to whisper-Silero, whose full-buffer rescans cannot keep up with
  # the roughly 10 ms CoreAudio callback cadence on this machine.
  src = fetchFromGitHub {
    owner = "silverstein";
    repo = "minutes";
    rev = "89537c314c41fd9b82709252346ff26c2cb685ac";
    hash = "sha256-0GpMzblFPmpNP8iJNqqgDQK3cd0exzKzGbbRThyNYeE=";
  };

  cargoHash = "sha256-Sacrf51x3pBxrLV0yO4arMrby7nhmrVYMf5jGPyGfRc=";

  nativeBuildInputs = [
    cmake
    pkg-config
    swift
  ];
  buildInputs = [ onnxruntime ];

  # Keep ort-sys fully inside Nix: use nixpkgs' runtime instead of its default
  # build-time download into ~/Library/Caches.
  ORT_LIB_LOCATION = "${onnxruntime}/lib";
  ORT_PREFER_DYNAMIC_LINK = "1";
  ORT_SKIP_DOWNLOAD = "1";
  MACOSX_DEPLOYMENT_TARGET = "14.4";

  # Nix's Swift wrapper carries its own deployment target and does not honor
  # MACOSX_DEPLOYMENT_TARGET for this build-script invocation. Upstream calls
  # swiftc directly, so make the already-required target explicit there too.
  postPatch = ''
    substituteInPlace crates/core/build.rs \
      --replace-fail '.arg("-O")' \
      '.arg("-O").args(["-target", "arm64-apple-macosx14.4"])'
  '';

  cargoBuildFlags = [
    "-p"
    "minutes-cli"
  ];
  buildFeatures = [
    "metal"
    "parakeet"
    "vad-ort"
  ];

  # Upstream's full workspace suite is not part of this package build. The
  # binary itself is exercised below after installation.
  doCheck = false;

  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/minutes" --version | grep -F "minutes ${finalAttrs.version}"
    "$out/bin/minutes" capabilities | grep -F "parakeet: yes"
    strings "$out/bin/minutes" | grep -F "recording sidecar using ort-Silero VAD"
  '';

  meta = {
    description = "Local-first meeting transcription and conversation memory";
    homepage = "https://github.com/silverstein/minutes";
    license = lib.licenses.mit;
    mainProgram = "minutes";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
