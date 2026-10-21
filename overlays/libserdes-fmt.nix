# avro-cpp 1.12's Exception.hh calls fmt::format but only includes
# <fmt/core.h>. Since fmt 11 that header no longer pulls in format.h unless
# FMT_DEPRECATED_HEAVY_CORE is defined, so every consumer of the header fails
# to compile against fmt 12. Here that is libserdes' C++ half, which breaks
# kcat and with it the whole Home Manager profile. Passing the define through
# --CXXFLAGS does not work: libserdes uses mklove, whose configure splits that
# value on whitespace and rejects the second token.
#
# The warning fires once nixpkgs moves past the avro-cpp release this was
# written for. Then check the new Exception.hh: drop this overlay if it
# includes <fmt/format.h>, otherwise bump the version below.
_final: prev: {
  libserdes =
    prev.lib.warnIf (prev.avro-cpp.version != "1.12.0")
      "overlays/libserdes-fmt.nix: avro-cpp is now ${prev.avro-cpp.version}; check whether libserdes still needs -DFMT_DEPRECATED_HEAVY_CORE"
      (
        prev.libserdes.overrideAttrs (old: {
          NIX_CFLAGS_COMPILE = toString [
            (old.NIX_CFLAGS_COMPILE or "")
            "-DFMT_DEPRECATED_HEAVY_CORE"
          ];
        })
      );
}
