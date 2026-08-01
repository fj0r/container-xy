use ../../bx *
use ../../bx/utils.nu

export def main [context: record = {}] {
    {
        from: $'($context.image):latest'
        user: master
        workdir: /home/master
        rust: {
            channel: stable
            frontend: sycamore
        }
        env: {
            RUSTUP_HOME: '/opt/rustup'
            CARGO_HOME: '/opt/cargo'
        }
    }
    | merge $context
    | build {|ctx|
        b conf env $ctx.env
        b conf path [ ($ctx.env.CARGO_HOME)/bin ]

        pkg install [
            rustup lldb
            musl
        ]

        mut cmps = []
        if $ctx.rust.channel == 'nightly' {
            $cmps ++= [rustc-codegen-cranelift]
        }

        mut bins = []
        if $ctx.rust.channel == 'nightly' {
            $bins ++= []
        } else {
            $bins ++= [rust-script]
        }

        mut ui_stack = []
        if ($ctx.rust.frontend? | is-not-empty) {
            $ui_stack ++= [frontend ui-($ctx.rust.frontend)]
        }

        $bins ++= utils resolve-stack [stacks cargo] $ui_stack []

        rust up $ctx.user $ctx.rust.channel --component [
            rust-src clippy rustfmt
            rust-analyzer
            ...$cmps
        ] --target [
            x86_64-unknown-linux-musl
            wasm32-wasip1 wasm32-wasip2 wasm32-unknown-unknown
        ] --bin [
            bacon cross bugstalker
            cargo-pgo cargo-bloat # cargo-profiler
            cargo-expand cargo-eval cargo-tree
            cargo-feature cargo-edit cargo-rail
            trunk cargo-wasi
            wasm-tools wit-deps-cli wit-bindgen-cli
            ...$bins
        ] --cargo-home $ctx.env.CARGO_HOME

        rust prefetch $ctx.user $ctx.workdir 'rust-labs' --stack [
            experimental ...$ui_stack
            cli codec error meta utils regex parser collections http
            logging data storage async concurrency web
            ecs wasm script system
        ] --cargo-home $ctx.env.CARGO_HOME
    }
}
