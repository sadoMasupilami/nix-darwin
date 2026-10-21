# Build fixes for kcat's Avro dependencies. Without them kcat, and with it the
# whole Home Manager profile, fails to build.
#
# libserdes: avro-cpp 1.12's Exception.hh calls fmt::format but only includes
# <fmt/core.h>. Since fmt 11 that header no longer pulls in format.h unless
# FMT_DEPRECATED_HEAVY_CORE is defined, so every consumer of the header fails
# to compile against fmt 12. Here that is libserdes' C++ half. Passing the
# define through --CXXFLAGS does not work: libserdes uses mklove, whose
# configure splits that value on whitespace and rejects the second token.
#
# avro-cpp: its CMakeLists adds -Werror for GCC only, and GCC 16 reports a
# false -Warray-bounds positive for the std::vector::push_back inlined into
# MapSchema's copy constructor (impl/Schema.cc). So the Linux build fails while
# clang on macOS builds it unchanged. Only that warning is turned off, and only
# for GCC, which keeps the cached macOS build.
#
# The warnings fire once nixpkgs moves past the avro-cpp release these were
# written for. Then check the new release: drop the libserdes fix if
# Exception.hh includes <fmt/format.h>, drop the avro-cpp fix if it builds with
# GCC, otherwise bump the version below.
_final: prev:
let
  inherit (prev) lib;
  outdated = prev.avro-cpp.version != "1.12.0";
  addCFlag =
    flag: old:
    toString [
      (old.NIX_CFLAGS_COMPILE or "")
      flag
    ];
in
{
  avro-cpp =
    if prev.stdenv.cc.isGNU then
      lib.warnIf outdated
        "overlays/kcat.nix: avro-cpp is now ${prev.avro-cpp.version}; check whether it still needs -Wno-array-bounds with GCC"
        (
          prev.avro-cpp.overrideAttrs (old: {
            NIX_CFLAGS_COMPILE = addCFlag "-Wno-array-bounds" old;
          })
        )
    else
      prev.avro-cpp;

  libserdes =
    lib.warnIf outdated
      "overlays/kcat.nix: avro-cpp is now ${prev.avro-cpp.version}; check whether libserdes still needs -DFMT_DEPRECATED_HEAVY_CORE"
      (
        prev.libserdes.overrideAttrs (old: {
          NIX_CFLAGS_COMPILE = addCFlag "-DFMT_DEPRECATED_HEAVY_CORE" old;
        })
      );
}
