#!/bin/sh
set -eu

# Thin ranlib wrapper around the pinned Zig's LLVM `ranlib`.
# Companion to zig_ar.sh — see that file for why jemalloc's autotools build
# needs a cross-capable AR/RANLIB instead of the macOS host tools.

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

  printf '%s\n' "zig ranlib wrapper: unable to find Zig executable" >&2
  return 127
}

exec "$(resolve_zig_exe)" ranlib "$@"
