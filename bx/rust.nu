use b.nu
use trace.nu
use utils.nu *
use hub.nu

export def up [
    owner
    channel
    --cargo-home: string
    --component: list
    --target: list
    --bin: list
] {
    trace inc-level
    b exec [
        $"rustup default ($channel)"
        $"rustup toolchain install ($channel)"
    ]

    hub install [mold sccache]

    if ($component | is-not-empty) {
        b exec [
            $"rustup component add ($component | str join ' ')"
        ]
        b with-mount {
            let dst = 'usr/bin' | path expand
            trace o -p 'rust-component' $dst
            for b in [rust-analyzer] {
                if ($b in $component) and not ($dst | path join $b | path exists) {
                    trace o -p 'fix-rustup-bin' $b
                    ln -sf /usr/bin/rustup ($dst | path join $b)
                }
            }
        }
    }
    if ($target | is-not-empty) {
        b exec [
            $"rustup target add ($target | str join ' ')"
        ]
    }
    if ($bin | is-not-empty) {
        b with-mount {
            let dst = 'usr/local/bin/' | path expand
            trace o -p 'cargo-binstall-dir' $dst
            let url = 'https://github.com/cargo-bins/cargo-binstall/releases/latest/download/cargo-binstall-x86_64-unknown-linux-musl.tgz'
            curl -fsSL $url | tar zxf - -C $dst
            chmod +x ($dst | path join cargo-binstall)
        }
        b exec [
            $"cargo binstall -y ($bin | str join ' ')"
        ]
    }

    let cargo_home = $env.CARGO_HOME? | default $cargo_home
    if ($cargo_home | is-not-empty) {
        b exec [
            $'rm -rf ($cargo_home)/registry/src/*'
            $'chown ($owner):($owner) -R ($cargo_home)'
        ]
        b with-mount {
            let linker = if ('usr/bin/clang' | path exists) {{
                linker: /usr/bin/clang
            }} else {{}}
            let ld = if ('usr/local/bin/mold' | path exists) {[
                -C, "link-arg=--ld-path=/usr/local/bin/mold"
                # -C, "codegen-units=16"
            ]} else {[]}
            let backend = if $channel == 'nightly' {{codegen-backend: cranelift}} else {{}}

            cd (relative-path $cargo_home)
            let cfg = {
              target: {
                "x86_64-unknown-linux-gnu": {
                  ...$linker
                  rustflags: [...$ld]
                }
              },
              build: {
                incremental: true,
                rustc-wrapper: sccache,
                target-dir: /tmp/target/cargo
              },
              profile: {
                dev: {
                  opt-level: 0,
                  debug: line-tables-only,
                  ...$backend,
                  package: {
                    *: { opt-level: 3, debug: false }
                  }
                },
                release: {
                  debug: 0
                  strip: true
                  opt-level: z
                  panic: abort
                  lto: fat
                  codegen-units: 1
                  # rustflags: [-C target-cpu=native]
                }
              }
            }
            | to toml
            trace o -p 'cargo/config.toml' $cfg
            $cfg | save config.toml
        }
    }

    b conf env {
        RUSTC_WRAPPER: '/usr/local/bin/sccache'
    }
}

export def prefetch [
    owner
    workdir
    proj
    pkgs: list<string> = []
    --stack(-s): list<string> = []
    --test
    --debug: string
    --cargo-home: string
] {
    trace inc-level
    # mkdir $dst
    b exec [
        $"cd ($workdir)"
        $"pwd"
        $"cargo new ($proj)"
        $"cd ($proj)"
        $"pwd"
    ]

    let pkgs = resolve-stack [stacks rust] $stack $pkgs

    let pkgs = $pkgs | reduce -f {} {|i,a|
        $a | insert $i '*'
    }

    b with-mount {
        let dst = relative-path $workdir | path expand
        let dstf = $dst | path join $proj Cargo.toml
        trace o -p 'prefetch' ($dstf | path relative-to $dst)
        if ($debug | is-not-empty) {
            {
                dst: $dst
                dstf: $dstf
            }
            | load-env
            use upterm.nu
            upterm $debug
        }

        cat $dstf | from toml | update dependencies $pkgs
        | do { let n = $in; print $n; $n }
        | save -f $dstf
    }

    if $test {
        b exec [$'cat ($workdir)/($proj)/Cargo.toml']
        return
    }

    mut post = [
        $"cd ($workdir | path join $proj)"
        "cargo fetch"
        $"cd ($workdir)"
        $"chown ($owner):($owner) -R ($proj)"
    ]

    if ($cargo_home | is-not-empty) {
        $post ++= [
            $'rm -rf ($cargo_home)/registry/src/*'
            $'chown ($owner):($owner) -R ($cargo_home)'
        ]
    }
    b exec $post
}
