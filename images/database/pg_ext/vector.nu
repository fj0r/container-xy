use ../../../bx *

export def main [xctx] {
    let pgrx  = $xctx.pgrx
    let tags  = $xctx.tags
    let context = $xctx.context
    let version = curl --retry 3 -fsSL https://api.github.com/repos/pgvector/pgvector/tags
    | from json
    | first
    | get name
    | str substring 1..
    let tag = $"pg_vector_($context.pg_version_major)_($version)"
    if ($tag not-in $tags) {
        {
            timezone: Asia/Shanghai
        }
        | merge $context
        | merge { from: 'scratch', tag: $tag }
        | build {|ctx|
            b conf workdir /app
            let dst = {
                from: $"($context.image):($pgrx)"
            }
            | build --no-commit {|ctx1|
                let pg_ver = $context.pg_version_major
                b exec [
                    $'curl --retry 3 -fsSL https://github.com/pgvector/pgvector/archive/refs/tags/v($version).tar.gz | tar -zxf - -C . --strip-components=1'
                    'make clean -j'
                    'make USE_PGXS=1 OPTFLAGS="" -j'
                    $'mkdir -p /out/lib/postgresql/($pg_ver)/lib'
                    $'cp *.so /out/lib/postgresql/($pg_ver)/lib'
                    $'mkdir -p /out/share/postgresql/($pg_ver)/extension'
                    $'cp *.control /out/share/postgresql/($pg_ver)/extension'
                    $'cp sql/*.sql /out/share/postgresql/($pg_ver)/extension'
                ]
            }

            b with-mount {|new, old|
                cd ($dst.BUILDAH_WORKING_MOUNTPOINT | path join out)
                cp -r * $new
            }

            buildah unmount $dst.BUILDAH_WORKING_CONTAINER
        }
    } else {
        trace o $tag exists
    }
    return $tag
}
