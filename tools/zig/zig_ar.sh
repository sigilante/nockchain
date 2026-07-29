#!/bin/sh
set -eu

# Thin archiver wrapper around the pinned Zig's LLVM `ar`.
#
# Why this exists: tikv-jemalloc-sys builds jemalloc via its bundled autotools
# `configure`+`make`, which read plain `AR`/`RANLIB` from the environment.
# cargo-zigbuild only injects the cc-crate-style `AR_<target>` wrapper (honored
# by ring/blake3/aws-lc), so jemalloc's autoconf falls back to the macOS host
# `ar`, which silently drops cross-compiled ELF objects and produces an empty
# `libjemalloc.a` (undefined `mallocx`/`rallocx`/`sdallocx` at link time).
# Pointing AR at this script makes jemalloc archive ELF objects correctly.

resolve_zig_exe() {
  if [ -n "${ZIG_EXE:-}" ] && [ -x "${ZIG_EXE}" ]; then
    printf '%s\n' "${ZIG_EXE}"
    return 0
  fi

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

  printf '%s\n' "zig ar wrapper: unable to find Zig executable" >&2
  return 127
}

exec "$(resolve_zig_exe)" ar "$@"
