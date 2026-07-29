"""Foundry toolchain providers for Bazel."""

FoundryToolchainInfo = provider(
    doc = "Foundry toolchain binaries.",
    fields = ["forge", "cast", "anvil", "chisel"],
)

def _foundry_toolchain_impl(ctx):
    return [
        platform_common.ToolchainInfo(
            foundry = FoundryToolchainInfo(
                forge = ctx.file.forge,
                cast = ctx.file.cast,
                anvil = ctx.file.anvil,
                chisel = ctx.file.chisel,
            ),
        ),
    ]

foundry_toolchain = rule(
    implementation = _foundry_toolchain_impl,
    attrs = {
        "forge": attr.label(allow_single_file = True, mandatory = True),
        "cast": attr.label(allow_single_file = True, mandatory = True),
        "anvil": attr.label(allow_single_file = True, mandatory = True),
        "chisel": attr.label(allow_single_file = True, mandatory = True),
    },
)
