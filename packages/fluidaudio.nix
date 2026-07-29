{
  fetchFromGitHub,
  fetchzip,
  lib,
  swiftPackages,
}:

let
  # FluidAudio's Swift package declares this xcframework as a remote binary
  # target. Fetch it through Nix and rewrite the manifest to the immutable
  # store path so SwiftPM never performs an undeclared network download.
  nemoTextProcessing = fetchzip {
    url = "https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.0/NemoTextProcessing.xcframework.zip";
    hash = "sha256-YiZfOM56/TfKv6OQzfL36x6Rt9GhISWdn1mZEfyp2H0=";
  };
in
swiftPackages.stdenv.mkDerivation {
  pname = "fluidaudio";
  version = "unstable-2026-07-25";

  src = fetchFromGitHub {
    owner = "FluidInference";
    repo = "FluidAudio";
    rev = "88d6d8166880dee1ac7c32c80f8e10cd782f8ca8";
    hash = "sha256-5sbDsLwxlKqn/y8RCv0+rIRqmqEV4svVhSvLh5i63Bk=";
  };

  nativeBuildInputs = [
    swiftPackages.swift
    swiftPackages.swiftpm
  ];

  MACOSX_DEPLOYMENT_TARGET = "14.0";

  postPatch = ''
    substituteInPlace Package.swift \
      --replace-fail '            url:
                "https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.0/NemoTextProcessing.xcframework.zip",
            checksum: "76d0ee9a32b1ee2193231299180ca9bc4fc7e98794e771b3d55d66498352d85f"' \
      '            path: "Vendor/NemoTextProcessing.xcframework"'

    mkdir -p Vendor
    ln -s ${nemoTextProcessing} Vendor/NemoTextProcessing.xcframework
  '';

  swiftpmFlags = [ "--product fluidaudiocli" ];

  doCheck = false;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$(swiftpmBinPath)/fluidaudiocli" "$out/bin/fluidaudio"
    ln -s fluidaudio "$out/bin/fluidaudiocli"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/fluidaudio" --help | grep -F "cohere-transcribe"
    "$out/bin/fluidaudio" --help | grep -F "transcribe"
  '';

  meta = {
    description = "Core ML speech transcription and diarization for Apple Silicon";
    homepage = "https://github.com/FluidInference/FluidAudio";
    license = lib.licenses.asl20;
    mainProgram = "fluidaudio";
    platforms = [ "aarch64-darwin" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
