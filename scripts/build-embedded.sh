#!/usr/bin/env bash
#
# Builds the native surrealdb.c static library that backs the embedded (mem://)
# engine, and assembles the slices into an XCFramework.
#
#   ./scripts/build-embedded.sh                        # host slice only (default)
#   ./scripts/build-embedded.sh --platforms macos,ios  # named platforms
#   ./scripts/build-embedded.sh --platforms apple      # everything
#   ./scripts/build-embedded.sh --slices aarch64-apple-ios
#   ./scripts/build-embedded.sh --assemble-only        # package what is already built
#
# Slices that fail are reported and skipped unless they are in
# scripts/embedded/required-slices.txt, so an unproven platform cannot break a
# build that only needed the proven ones.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/embedded/pin.env
source scripts/embedded/pin.env

SRC="$ROOT/.build/embedded/surrealdb.c"
OUT="$ROOT/.build/embedded/out"
HOST_TRIPLE="$(rustc -vV | awk '/^host:/{print $2}')"

# triple | sdk | deployment-target env var | version | needs -Z build-std
SLICE_TABLE=(
  "aarch64-apple-darwin|macosx|MACOSX_DEPLOYMENT_TARGET|14.0|0"
  "x86_64-apple-darwin|macosx|MACOSX_DEPLOYMENT_TARGET|14.0|0"
  "aarch64-apple-ios|iphoneos|IPHONEOS_DEPLOYMENT_TARGET|17.0|0"
  "aarch64-apple-ios-sim|iphonesimulator|IPHONEOS_DEPLOYMENT_TARGET|17.0|0"
  "x86_64-apple-ios|iphonesimulator|IPHONEOS_DEPLOYMENT_TARGET|17.0|0"
  "aarch64-apple-tvos|appletvos|TVOS_DEPLOYMENT_TARGET|17.0|0"
  "aarch64-apple-tvos-sim|appletvsimulator|TVOS_DEPLOYMENT_TARGET|17.0|0"
  "aarch64-apple-visionos|xros|XROS_DEPLOYMENT_TARGET|1.0|0"
  "aarch64-apple-visionos-sim|xrsimulator|XROS_DEPLOYMENT_TARGET|1.0|0"
  "aarch64-apple-watchos-sim|watchsimulator|WATCHOS_DEPLOYMENT_TARGET|10.0|0"
  "arm64_32-apple-watchos|watchos|WATCHOS_DEPLOYMENT_TARGET|10.0|1"
)

platform_slices() {
  case "$1" in
    macos)    echo "aarch64-apple-darwin x86_64-apple-darwin" ;;
    ios)      echo "aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios" ;;
    tvos)     echo "aarch64-apple-tvos aarch64-apple-tvos-sim" ;;
    visionos) echo "aarch64-apple-visionos aarch64-apple-visionos-sim" ;;
    watchos)  echo "aarch64-apple-watchos-sim arm64_32-apple-watchos" ;;
    apple|all)
      echo "$(platform_slices macos) $(platform_slices ios) $(platform_slices tvos)" \
           "$(platform_slices visionos) $(platform_slices watchos)" ;;
    *) echo "unknown platform: $1" >&2; exit 2 ;;
  esac
}

slice_field() {
  local triple="$1" field="$2" row
  for row in "${SLICE_TABLE[@]}"; do
    if [[ "${row%%|*}" == "$triple" ]]; then
      echo "$row" | cut -d'|' -f"$field"
      return 0
    fi
  done
  return 1
}

SLICES="$HOST_TRIPLE"
ASSEMBLE_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platforms)
      SLICES=""
      IFS=',' read -ra requested <<< "$2"
      for platform in "${requested[@]}"; do
        SLICES+=" $(platform_slices "$platform")"
      done
      shift 2 ;;
    --slices)        SLICES="${2//,/ }"; shift 2 ;;
    --assemble-only) ASSEMBLE_ONLY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

fetch_source() {
  mkdir -p "$SRC"
  if [[ ! -d "$SRC/.git" ]]; then
    git -C "$SRC" init -q
    git -C "$SRC" remote add origin "$SURREALDB_C_REPO"
  fi
  git -C "$SRC" fetch --depth 1 origin "$SURREALDB_C_REF"
  git -C "$SRC" checkout --force -q FETCH_HEAD

  # A shallow fetch by SHA can land on a moved ref on some server configs.
  local head
  head="$(git -C "$SRC" rev-parse HEAD)"
  if [[ "$head" != "$SURREALDB_C_REF" ]]; then
    echo "pin mismatch: wanted $SURREALDB_C_REF, got $head" >&2
    exit 1
  fi

  # build.rs cc-compiles this on every target; it is test scaffolding and has no
  # business in a cross-compile.
  rm -rf "$SRC/c_test"
}

build_slice() {
  local triple="$1"
  local sdk depvar depver build_std
  sdk="$(slice_field "$triple" 2)"
  depvar="$(slice_field "$triple" 3)"
  depver="$(slice_field "$triple" 4)"
  build_std="$(slice_field "$triple" 5)"

  echo "==> $triple"

  # Only arm64_32-apple-watchos lacks a prebuilt std. macOS ships bash 3.2,
  # where expanding an empty array under `set -u` is itself an error, so the
  # nightly prefix is applied by branching rather than by splatting an array
  # that is usually empty.
  local -a cargo_args=(build --release --locked --target "$triple")
  if [[ "$build_std" == "1" ]]; then
    cargo_args+=(-Z build-std=std,panic_abort)
  fi

  local underscored="${triple//-/_}"
  (
    cd "$SRC"
    export SDKROOT; SDKROOT="$(xcrun --sdk "$sdk" --show-sdk-path)"
    export "${depvar}=${depver}"
    export "CC_${underscored}=$(xcrun --sdk "$sdk" --find clang)"
    export "AR_${underscored}=$(xcrun --sdk "$sdk" --find ar)"
    export CARGO_TARGET_DIR="$SRC/target"
    if [[ "$build_std" == "1" ]]; then
      cargo "+${RUST_NIGHTLY:-nightly}" "${cargo_args[@]}"
    else
      cargo "${cargo_args[@]}"
    fi
  ) || return 1

  # `set -e` is suppressed inside a function invoked from an `if`, so each step
  # below has to report its own failure or a broken slice ships silently.
  local built="$SRC/target/$triple/release/libsurrealdb_c.a"
  [[ -f "$built" ]] || return 1

  mkdir -p "$OUT/slices/$triple"
  cp "$built" "$OUT/slices/$triple/libsurrealdb_c.a" || return 1
  strip -x -S "$OUT/slices/$triple/libsurrealdb_c.a" || return 1
  ranlib "$OUT/slices/$triple/libsurrealdb_c.a" 2>/dev/null || true
  lipo -info "$OUT/slices/$triple/libsurrealdb_c.a" >/dev/null 2>&1 || return 1
}

fat_slice() {
  local name="$1"; shift
  local -a present=()
  for triple in "$@"; do
    [[ -f "$OUT/slices/$triple/libsurrealdb_c.a" ]] && present+=("$OUT/slices/$triple/libsurrealdb_c.a")
  done
  [[ "${#present[@]}" -gt 0 ]] || return 1

  mkdir -p "$OUT/fat/$name"
  lipo -create "${present[@]}" -output "$OUT/fat/$name/libsurrealdb_c.a"
}

FAILED_SLICES=()

if [[ "$ASSEMBLE_ONLY" -eq 0 ]]; then
  fetch_source
  for triple in $SLICES; do
    if ! slice_field "$triple" 1 >/dev/null; then
      echo "unknown slice: $triple" >&2
      exit 2
    fi
    rustup target add "$triple" >/dev/null 2>&1 || true
    if ! build_slice "$triple"; then
      echo "!!! slice $triple failed" >&2
      rm -rf "$OUT/slices/$triple"
      FAILED_SLICES+=("$triple")
    fi
  done
fi

mkdir -p "$OUT/include"
cp "$SRC/include/surrealdb.h" "$OUT/include/"
cp "$ROOT/scripts/embedded/module.modulemap" "$OUT/include/"

# pkg-config is how the CSurrealDB system-library target finds the header and the
# archive, so the manifest needs no unsafe flags.
mkdir -p "$OUT/pkgconfig"
cat > "$OUT/pkgconfig/surrealdb_c.pc" <<PC
Name: surrealdb_c
Description: SurrealDB C FFI, built from surrealdb.c @ ${SURREALDB_C_REF}
Version: 0.1.0
Cflags: -I${OUT}/include
Libs: -L${OUT}/slices/${HOST_TRIPLE} -lsurrealdb_c -framework Security -framework CoreFoundation -framework SystemConfiguration -lresolv -lc++
PC

# Assemble an XCFramework from whatever slices exist.
fat_slice macos          aarch64-apple-darwin x86_64-apple-darwin      || true
fat_slice ios            aarch64-apple-ios                             || true
fat_slice ios-simulator  aarch64-apple-ios-sim x86_64-apple-ios        || true
fat_slice tvos           aarch64-apple-tvos                            || true
fat_slice tvos-simulator aarch64-apple-tvos-sim                        || true
fat_slice xros           aarch64-apple-visionos                        || true
fat_slice xros-simulator aarch64-apple-visionos-sim                    || true
fat_slice watchos        arm64_32-apple-watchos                        || true
fat_slice watchos-simulator aarch64-apple-watchos-sim                  || true

XCFRAMEWORK="$OUT/CSurrealDB.xcframework"
XC_ARGS=()
for fat in "$OUT"/fat/*/libsurrealdb_c.a; do
  [[ -f "$fat" ]] || continue
  XC_ARGS+=(-library "$fat" -headers "$OUT/include")
done

if [[ "${#XC_ARGS[@]}" -gt 0 ]]; then
  rm -rf "$XCFRAMEWORK"
  xcodebuild -create-xcframework "${XC_ARGS[@]}" -output "$XCFRAMEWORK" >/dev/null
  echo "==> $XCFRAMEWORK"
fi

if [[ "${#FAILED_SLICES[@]}" -gt 0 ]]; then
  echo "==> failed slices: ${FAILED_SLICES[*]}" >&2
  if [[ -f "$ROOT/scripts/embedded/required-slices.txt" ]]; then
    while read -r required; do
      [[ -n "$required" && "$required" != \#* ]] || continue
      for failed in "${FAILED_SLICES[@]}"; do
        if [[ "$failed" == "$required" ]]; then
          echo "required slice $required failed" >&2
          exit 1
        fi
      done
    done < "$ROOT/scripts/embedded/required-slices.txt"
  fi
fi

echo "==> native slices in $OUT/slices"
echo "==> export PKG_CONFIG_PATH=$OUT/pkgconfig"
