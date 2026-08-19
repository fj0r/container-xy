use ../../../bx *

export def main [xctx] {
    let pgrx  = $xctx.pgrx
    let tags  = $xctx.tags
    let context = $xctx.context
    hub sync {
        cfg: {
            repo: 'amutu/zhparser'
            version: ['substr 1']
        }
        tag: $"pg_zhparser_($context.pg_version_major)_{version}"
        obj: $tags
    } {|cx|
        {
            timezone: Asia/Shanghai
        }
        | merge $context
        | merge { from: 'scratch', tag: $cx.tag }
        | build {|ctx|
            conf workdir /
            let dst = {
                from: $"($context.image):($pgrx)"
            }
            | build --no-commit {|ctx1|
                let pg_ver = $context.pg_version_major
                b exec [
                    'opwd=$(pwd)'
                    'curl -sSL http://www.xunsearch.com/scws/down/scws-1.2.3.tar.bz2 | tar -jxf -'
                    'cd scws-1.2.3'
                    './configure'
                    'DESTDIR=/scws make install'
                    'cd /scws/usr/local'
                    'tar -cvf /scws.tar *'
                    'cd $opwd'
                    'tar -xf /scws.tar -C /usr/local'
                    $'curl -sSL https://github.com/amutu/zhparser/archive/refs/tags/v($cx.version).tar.gz | tar -zxf - -C . --strip-component=1'
                    'make -j$(nproc)'
                    'DESTDIR=/out make install'
                    'tar -xf /scws.tar -C /out/usr'
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
