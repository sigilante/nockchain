"Expose protoc from the registered protobuf toolchain."

def _protoc_from_toolchain_impl(ctx):
    toolchain = ctx.toolchains[Label("@protobuf//bazel/private:proto_toolchain_type")]
    proto_compiler = toolchain.proto.proto_compiler
    protoc = getattr(proto_compiler, "executable", proto_compiler)
    out = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.run_shell(
        inputs = [protoc],
        outputs = [out],
        command = "cp \"$1\" \"$2\" && chmod +x \"$2\"",
        arguments = [protoc.path, out.path],
    )
    return DefaultInfo(
        files = depset([out]),
        executable = out,
        runfiles = ctx.runfiles([out]),
    )

protoc_from_toolchain = rule(
    implementation = _protoc_from_toolchain_impl,
    executable = True,
    toolchains = ["@protobuf//bazel/private:proto_toolchain_type"],
)
