use ../../../bx *

export def main [xctx] {
    let pgrx  = $xctx.pgrx
    let tags  = $xctx.tags
    let context = $xctx.context
    hub sync {
        cfg: {
            repo: 'duckdb/pg_duckdb'
            version: ['substr 1']
        }
        tag: $"pg_duckdb_($context.pg_version_major)_{version}"
        obj: $tags
    } {|cx|
        {
            timezone: Asia/Shanghai
        }
        | merge $context
        | merge { from: 'scratch', tag: $cx.tag }
        | build {|ctx|
            b conf workdir /
            let dst = {
                from: $"($context.image):($pgrx)"
            }
            | build --no-commit {|ctx1|
                b exec [
                    'git clone --depth=1 https://github.com/duckdb/pg_duckdb.git'
                    'cd pg_duckdb'
                    'git submodule update --init --recursive'
                    'make -j$(nproc)'
                    'DESTDIR=/out make install'
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
