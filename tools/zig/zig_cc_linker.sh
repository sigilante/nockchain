#!/bin/sh
set -eu

# Default to the same Linux x86_64/glibc floor cargo-zigbuild uses unless
# callers explicitly request a different glibc floor via ZIG_TARGET.
target="${ZIG_TARGET:-x86_64-linux-gnu.2.39}"
# cargo-zigbuild accepts Rust-style triples (x86_64-unknown-linux-gnu.*), but
# zig expects the vendorless form for versioned glibc targets.
case "${target}" in
  *-unknown-linux-gnu*)
    target="$(printf '%s\n' "${target}" | sed 's/-unknown-linux-gnu/-linux-gnu/')"
    ;;
esac
case "${target}" in
  aarch64-*)
    default_dynamic_linker="/lib/ld-linux-aarch64.so.1"
    ;;
  x86_64-*)
    default_dynamic_linker="/lib64/ld-linux-x86-64.so.2"
    ;;
  *)
    default_dynamic_linker="/lib64/ld-linux-x86-64.so.2"
    ;;
esac
dynamic_linker="${ZIG_DYNAMIC_LINKER:-${default_dynamic_linker}}"
tmp_root="${TMPDIR:-/tmp}"
zig_cache_prefix="${ZIG_CACHE_PREFIX:-${RULES_ZIG_CACHE_PREFIX_LINUX:-${RULES_ZIG_CACHE_PREFIX:-/tmp/zig-cache}}}"

# Zig needs writable cache/appdata dirs in the action sandbox.
if [ -z "${HOME:-}" ]; then
  HOME="${zig_cache_prefix}/home"
  export HOME
fi
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${zig_cache_prefix}/xdg-cache}"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-${zig_cache_prefix}/global}"
export ZIG_LOCAL_CACHE_DIR="${ZIG_LOCAL_CACHE_DIR:-${zig_cache_prefix}/local}"

resolve_zig_exe() {
  if [ -n "${ZIG_EXE:-}" ] && [ -x "${ZIG_EXE}" ]; then
    printf '%s\n' "${ZIG_EXE}"
    return 0
  fi

  # Prefer hermetic Zig fetched by rules_zig and staged as a compile input.
  for path in \
    external/rules_zig++zig+zig_*/zig \
    external/zig_*/zig
  do
    if [ -x "${path}" ]; then
      printf '%s\n' "${path}"
      return 0
    fi
  done

  if command -v zig >/dev/null 2>&1; then
    command -v zig
    return 0
  fi

  printf '%s\n' "zig linker wrapper: unable to find Zig executable" >&2
  return 127
}

zig_exe="$(resolve_zig_exe)"
zig_driver="${ZIG_CC_MODE:-cc}"

# Some autoconf/cmake probes invoke the compiler with only a version flag.
# Zig emits a spurious target-parse error for versioned glibc targets in this
# mode, so bypass -target for pure version queries.
if [ "$#" -eq 1 ]; then
  case "$1" in
    --version | -v | -V | -qversion)
      exec "${zig_exe}" "${zig_driver}" "$1"
      ;;
  esac
fi

# rustc emits a few GCC-specific linker flags that zig cc does not accept.
tmp_args_file="${TMPDIR:-/tmp}/zig_cc_linker_args.$$"
: > "${tmp_args_file}"
expect_target_value=0
# --dynamic-linker is a link-time flag; zig cc rejects it on compile-only
# (-c), preprocess-only (-E), or assemble-only (-S) invocations with
# "object files cannot specify --dynamic-linker". aws-lc-sys drives this
# wrapper (via AWS_LC_SYS_CC) for exactly those probe steps, so only inject
# the dynamic linker on actual link steps.
link_step=1
for arg in "$@"; do
  if [ "${expect_target_value}" -eq 1 ]; then
    expect_target_value=0
    continue
  fi

  case "${arg}" in
    -c | -E | -S)
      link_step=0
      printf '%s\n' "${arg}" >> "${tmp_args_file}"
      continue
      ;;
  esac

  case "${arg}" in
    --target | -target)
      # The wrapper sets -target explicitly; ignore incoming target flags.
      expect_target_value=1
      ;;
    --target=* | -target=*)
      ;;
    -Wl,-no-as-needed)
      printf '%s\n' "-Wl,--no-as-needed" >> "${tmp_args_file}"
      ;;
    -Wl,--push-state,-as-needed)
      printf '%s\n' "-Wl,--as-needed" >> "${tmp_args_file}"
      ;;
    -Wl,--pop-state)
      ;;
    -Wl,-lto_library,*)
      ;;
    -Wl,-cache_path_lto,*)
      ;;
    -Wp,-U_FORTIFY_SOURCE)
      # Zig's clang driver rejects this GCC-style preprocessor passthrough,
      # but accepts the equivalent undefine flag directly.
      printf '%s\n' "-U_FORTIFY_SOURCE" >> "${tmp_args_file}"
      ;;
    -pass-exit-codes)
      ;;
    *)
      printf '%s\n' "${arg}" >> "${tmp_args_file}"
      ;;
  esac
done

set --
while IFS= read -r arg; do
  set -- "$@" "$arg"
done < "${tmp_args_file}"

if [ "${link_step}" -eq 1 ]; then
  exec "${zig_exe}" "${zig_driver}" -target "$target" -Wl,--dynamic-linker="$dynamic_linker" "$@"
fi
exec "${zig_exe}" "${zig_driver}" -target "$target" "$@"
