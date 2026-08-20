use ../../../bx *

export def main [xctx] {
    let pgrx  = $xctx.pgrx
    let tags  = $xctx.tags
    let context = $xctx.context
    hub sync {
        cfg: {
            repo: 'paradedb/paradedb'
            version: ['substr 1']
        }
        tag: $"pg_search_($context.pg_version_major)_{version}"
        obj: $tags
    } {|cx|
        {
            timezone: Asia/Shanghai
        }
        | merge $context
        | merge { from: 'scratch', tag: $cx.tag }
        | build {|ctx|
            b conf workdir /app
            let dst = {
                from: $"($context.image):($pgrx)"
            }
            | build --no-commit {|ctx1|
                let pg_ver = $context.pg_version_major
                b exec [
                    $'curl --retry 3 -fsSL https://github.com/paradedb/paradedb/archive/refs/tags/v($cx.version).tar.gz | tar -zxf - -C . --strip-components=1'
                    'pgrx_need=$(grep -m1 "pgrx =" Cargo.toml | sed -E "s/.*pgrx = \"?=?([0-9.]+).*/\1/")'
                    'pgrx_cur=$(cargo pgrx --version 2>/dev/null | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)'
                    'if [ "$pgrx_cur" != "$pgrx_need" ]; then cargo install --locked cargo-pgrx --version "$pgrx_need"; fi'
                    'cd pg_search'
                    $'cargo pgrx package --package pg_search --pg-config /usr/lib/postgresql/($pg_ver)/bin/pg_config'
                    'mkdir -p /out/usr'
                    'cp -r target/release/pg_search-pg*/usr/* /out/usr/'
                ]
            }

            b with-mount {|new, old|
                cd ($dst.BUILDAH_WORKING_MOUNTPOINT | path join out/usr)
                cp -r * $new
            }

            buildah unmount $dst.BUILDAH_WORKING_CONTAINER
        }
    }
}