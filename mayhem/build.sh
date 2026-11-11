#!/usr/bin/env bash
#
# mayhem/build.sh — build newsboat's fuzz harnesses (sanitized) and its own test suite (normal flags).
# Runs inside the commit image as `mayhem` in /mayhem. Re-runnable and offline: the cargo registry is
# in $CARGO_HOME (/opt/toolchains/rust/cargo), filled by the first online run.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${CARGO_HOME:=/opt/toolchains/rust/cargo}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS CARGO_HOME

cd "$SRC"

HARNESSES="fuzz_htmlrenderer fuzz_tagsoup fuzz_rsspp fuzz_matcher fuzz_textformatter"
# upstream's Makefile writes objects next to the sources; start each phase from a clean slate.
clean_objects() {
  find src rss filter test 3rd-party -name '*.o' -delete
  rm -f libboat.a libfilter.a librsspp.a
}

# config.sh feeds config.mk (libs/defines) from pkg-config.
rm -f config.mk
./config.sh >/dev/null

# 1) TEST suite, project's NORMAL flags (no sanitizers, no -gdwarf-3). The Rust crates build here too:
#    libnewsboat.a (reused by the sanitized build below, as it carries no C++ instrumentation) and the
#    cargo test binaries.
clean_objects
env -u CFLAGS -u CXXFLAGS -u LDFLAGS CXXFLAGS="$COVERAGE_FLAGS" make -j"$MAYHEM_JOBS" test

# 2) Sanitized + SanCov-instrumented project objects/libraries for the fuzz harnesses.
FUZZ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"
clean_objects
SRC_OBJS=$(ls src/*.cpp | sed 's/\.cpp$/.o/')
# The Coco/R-generated filter scanner/parser bump-allocates Tokens at 4-byte-aligned addresses (wchar_t-sized
# steps) and hashes strings in a signed int (coco_string_hash wraps), so every parse of a non-trivial
# expression trips -fsanitize=alignment / signed-integer-overflow. Relax only those two checks, only for
# the two generated objects; ASan and the rest of UBSan stay halting everywhere.
# shellcheck disable=SC2086
env -u CFLAGS -u LDFLAGS CXXFLAGS="$FUZZ_FLAGS -fno-sanitize=alignment,signed-integer-overflow" make filter/Scanner.o filter/Parser.o
# shellcheck disable=SC2086
env -u CFLAGS -u LDFLAGS CXXFLAGS="$FUZZ_FLAGS" make -j"$MAYHEM_JOBS" libboat.a libfilter.a librsspp.a $SRC_OBJS

# Compile/link flags exactly as upstream's Makefile computes them.
print_var() { printf 'print-%%:\n\t@echo $($*)\n' | CXXFLAGS="$FUZZ_FLAGS" make -s -f Makefile -f - "print-$1"; }
CXX_ALL_FLAGS=$(print_var CXXFLAGS)
LD_ALL_FLAGS=$(print_var LDFLAGS)
LIBS="-lboat -lnewsboat -lfilter -lrsspp -lpthread -ldl"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Leak sanitizer off at build time (SPEC §6.2 item 15); the standalone driver is C, so compile it as C.
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$TMP/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$TMP/standalone_main.o"

for h in $HARNESSES; do
  # shellcheck disable=SC2086
  $CXX $CXX_ALL_FLAGS -Wno-error -c "mayhem/$h.cpp" -o "$TMP/$h.o"
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$TMP/$h.o" "$TMP/lsan_off.o" $SRC_OBJS \
      $LIBS $LD_ALL_FLAGS -o "/mayhem/$h"
  # shellcheck disable=SC2086
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS "$TMP/$h.o" "$TMP/lsan_off.o" "$TMP/standalone_main.o" $SRC_OBJS \
      $LIBS $LD_ALL_FLAGS -o "/mayhem/$h-standalone"
done
