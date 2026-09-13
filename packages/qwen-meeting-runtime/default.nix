{
  lib,
  stdenvNoCC,
  fetchurl,
  linkFarm,
  python313,
  uv,
}:
let
  lock = builtins.fromTOML (builtins.readFile ../../config/qwen-meeting/runtime/uv.lock);
  # Target Python 3.13 on Apple Silicon. Prefer the lowest supported macOS
  # deployment target, so the same closure works from macOS 14 onward.
  compatible =
    wheel:
    builtins.match ".*-(cp313-cp313|cp3[0-9]-abi3|py3-none|py2.py3-none)-(any|macosx_(10|11|12|13|14)_[0-9]+_(arm64|universal2))\\.whl" wheel.url
    != null;
  selectWheel =
    package:
    let
      wheels = lib.sort (a: b: baseNameOf a.url < baseNameOf b.url) (
        builtins.filter compatible (package.wheels or [ ])
      );
    in
    if wheels == [ ] then
      throw "No locked Apple Silicon / Python 3.13 wheel for ${package.name}"
    else
      builtins.head wheels;
  wheelhouse = linkFarm "qwen-meeting-wheels" (
    map (
      package:
      let
        wheel = selectWheel package;
      in
      {
        name = baseNameOf wheel.url;
        path = fetchurl {
          inherit (wheel) url;
          hash = wheel.hash;
        };
      }
    ) (builtins.filter (p: p.source ? registry) lock.package)
  );
in
stdenvNoCC.mkDerivation {
  pname = "qwen-meeting-runtime";
  version = "0.3.5";
  src = ../../config/qwen-meeting/runtime;
  nativeBuildInputs = [
    python313
    uv
  ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    export UV_CACHE_DIR="$TMPDIR/uv-cache"
    export UV_PYTHON_DOWNLOADS=never
    uv export --locked --offline --no-dev --no-emit-project --output-file requirements.txt
    uv venv --offline --python ${python313}/bin/python3.13 "$out"
    uv pip sync --offline --python "$out/bin/python" --no-index \
      --find-links ${wheelhouse} --require-hashes requirements.txt
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    uv pip check --python "$out/bin/python"
    "$out/bin/mlx-qwen3-asr" --help >/dev/null
    # fetch-models.py imports huggingface_hub lazily, so cover it here too.
    "$out/bin/python" -c 'import huggingface_hub, mlx.core, nagisa, numpy, scipy'
  '';
  # Wheel binaries already carry their vendor signing/layout. Do not strip or
  # rewrite their Mach-O files in the generic fixup phase.
  dontFixup = true;
  meta = {
    description = "Immutable Qwen meeting runtime from the committed uv.lock";
    platforms = [ "aarch64-darwin" ];
  };
}
