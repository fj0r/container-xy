use ../../../bx *

export def main [xctx] {
    let tags  = $xctx.tags
    let context = $xctx.context
    let pg_ver = $context.pg_version_major
    hub sync {
        cfg: {
            repo: 'pgcentralfoundation/pgrx'
            version: ['substr 1']
        }
        tag: $"pgrx_($pg_ver)_{version}"
        obj: $tags
    } {|cx|
        {
            pgrx_version: $cx.version
            from: 'postgres'
            timezone: Asia/Shanghai
        }
        | merge $context
        | merge { tag: $cx.tag }
        | build {|ctx|
            pkg refresh
            [
                sudo
                ca-certificates
                lsb-release
                build-essential
                binutils
                m4
                gnupg
                curl
                jq
                git
                make
                gcc
                g++
                lld
                cmake
                clang
                libclang-dev
                ninja-build
                libssl-dev
                libcurl4-openssl-dev
                liblz4-dev
                libpq-dev
                postgresql-server-dev-($pg_ver)
                tree
                rustup

                pkg-config
                uuid-dev
                python3-dev
                libkrb5-dev

                libopenblas-dev
                libreadline-dev zlib1g-dev flex bison libxml2-dev libxslt-dev
                libssl-dev libxml2-utils xsltproc
                pkg-config libc++-dev libc++abi-dev libglib2.0-dev
                libtinfo6 libicu-dev libstdc++-12-dev liblz4-dev
            ]
            | uniq
            | pkg install $in

            setup timezone $ctx.timezone
            setup git 'root'
            nushell setup '/usr/local' {
                user: 'root'
                xdg_config: '/root/.config'
                plugins: [query]
            }

            rust up 'root' stable

            b exec [
                'cargo install cargo-get'
                $'cargo install --locked cargo-pgrx --version ($ctx.pgrx_version)'
                $'cargo pgrx init --pg($pg_ver)=/usr/lib/postgresql/($pg_ver)/bin/pg_config'
            ]
        }
    }
}
