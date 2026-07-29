{
  fetchFromGitHub,
  fetchzip,
  lib,
  stdenvNoCC,
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
stdenvNoCC.mkDerivation {
  pname = "fluidaudio";
  version = "unstable-2026-07-25";

  src = fetchFromGitHub {
    owner = "FluidInference";
    repo = "FluidAudio";
    rev = "88d6d8166880dee1ac7c32c80f8e10cd782f8ca8";
    hash = "sha256-5sbDsLwxlKqn/y8RCv0+rIRqmqEV4svVhSvLh5i63Bk=";
  };

  # FluidAudio uses Swift 6 ownership syntax and Core ML APIs newer than the
  # Swift 5.10 SDK currently provided by this pinned nixpkgs. Declare the Apple
  # Command Line Tools as an explicit host dependency and reject unexpected
  # compiler versions, while keeping all sources and model tooling Nix-pinned.
  __impureHostDeps = [
    "/Library/Developer/CommandLineTools"
  ];

  MACOSX_DEPLOYMENT_TARGET = "14.0";
  DEVELOPER_DIR = "/Library/Developer/CommandLineTools";

  postPatch = ''
    substituteInPlace Package.swift \
      --replace-fail '            url:' \
      '            path: "Vendor/NemoTextProcessing.xcframework"' \
      --replace-fail '                "https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.0/NemoTextProcessing.xcframework.zip",' \
      "" \
      --replace-fail '            checksum: "76d0ee9a32b1ee2193231299180ca9bc4fc7e98794e771b3d55d66498352d85f"' \
      ""

    mkdir -p Vendor
    ln -s ${nemoTextProcessing} Vendor/NemoTextProcessing.xcframework
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    swift_bin="/Library/Developer/CommandLineTools/usr/bin/swift"
    swift_version="$($swift_bin --version | head -n 1)"
    case "$swift_version" in
      *"Apple Swift version 6.3.3"*) ;;
      *)
        echo "Unsupported Apple Swift toolchain: $swift_version" >&2
        exit 1
        ;;
    esac

    # stdenv's compiler flags point at nixpkgs' older macOS SDK. FluidAudio
    # needs the matching Swift 6.3/Core ML SDK pair from the host CLT, so keep
    # that toolchain self-contained instead of mixing the two SDKs.
    unset NIX_CC NIX_CFLAGS_COMPILE NIX_CFLAGS_LINK
    unset NIX_LDFLAGS NIX_LDFLAGS_BEFORE NIX_BINTOOLS
    unset CC CXX LD AR
    export HOME="$TMPDIR/home"
    export CFFIXED_USER_HOME="$HOME"
    export XDG_CACHE_HOME="$HOME/.cache"
    export SWIFTPM_MODULECACHE_OVERRIDE="$HOME/.cache/swiftpm/modulecache"
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
    export MACOSX_DEPLOYMENT_TARGET="14.0"
    mkdir -p "$HOME" "$SWIFTPM_MODULECACHE_OVERRIDE"

    # CLT 26.6 accidentally ships a stale Swift 5.10 private
    # PackageDescription interface next to its Swift 6.3 dylib. SwiftPM
    # prefers that incompatible file. Give it an isolated copy in which the
    # matching public interface also serves private imports; never modify the
    # host toolchain itself.
    swiftpm_libs="$TMPDIR/swiftpm-libs"
    mkdir -p "$swiftpm_libs/ManifestAPI"
    cp -R "/Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI/." \
      "$swiftpm_libs/ManifestAPI/"
    for arch in arm64 x86_64; do
      cp \
        "$swiftpm_libs/ManifestAPI/PackageDescription.swiftmodule/$arch-apple-macos.swiftinterface" \
        "$swiftpm_libs/ManifestAPI/PackageDescription.swiftmodule/$arch-apple-macos.private.swiftinterface"
    done
    export SWIFTPM_CUSTOM_LIBS_DIR="$swiftpm_libs"

    "$swift_bin" build \
      --disable-sandbox \
      --scratch-path "$TMPDIR/swift-build" \
      -c release \
      --product fluidaudiocli

    runHook postBuild
  '';

  doCheck = false;

  installPhase = ''
    runHook preInstall
    bin_path="$(/Library/Developer/CommandLineTools/usr/bin/swift build \
      --scratch-path "$TMPDIR/swift-build" \
      -c release \
      --show-bin-path)"
    install -Dm755 "$bin_path/fluidaudiocli" "$out/bin/fluidaudio"
    ln -s fluidaudio "$out/bin/fluidaudiocli"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    "$out/bin/fluidaudio" transcribe --help 2>&1 \
      | grep -F -- "--model-version <v2|v3|110m>"
    "$out/bin/fluidaudio" transcribe --help 2>&1 \
      | grep -F -- "--output-json <file>"
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
