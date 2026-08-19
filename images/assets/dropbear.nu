use ../../bx *

export def main [context: record = {}] {
    $context
    | update image {|x|
        $x.image | path split | slice ..-2 | append 'assets' | path join
    }
    | merge {
        from: scratch
        tag: 'dropbear'
    }
    | build {|ctx|
        let dropbear = { from: 'debian:sid-slim' }
        | build --no-commit {|ctx|
            pkg install [
                # curl jq ca-certificates
                # git gnupg
                build-essential
                automake autoconf
                # libz libcrypto
                libssl-dev zlib1g-dev
            ]
            let url = (
                curl --retry 3 -fsSL
                https://api.github.com/repos/mkj/dropbear/releases
                -H 'Accept: application/vnd.github.v3+json'
                | jq -r '.[0].tarball_url'
            )
            trace o {dropbear: $url}
            b with-mount {
                mkdir build/dropbear
                curl -fsSL $url | tar -zxf - -C build/dropbear --strip-component=1
            }
            b exec [
                'cd /build/dropbear'
                'autoconf'
                'autoheader'
                'echo "#define DROPBEAR_SVR_PASSWORD_AUTH 0" > localoptions.h'
                './configure --enable-static'
                'make PROGRAMS="dropbear dbclient scp dropbearkey dropbearconvert"'
                'mkdir -p /target/bin'
                'mv dbclient dropbear scp dropbearkey dropbearconvert /target/bin'
            ]
            b with-mount {
                cd build
                git clone --depth=1 https://github.com/openssh/openssh-portable.git
            }
            b exec [
                'cd /build/openssh-portable'
                'autoreconf'
                './configure'
                'make sftp-server'
                'mkdir -p /target/libexec'
                'mv sftp-server /target/libexec'
            ]
        }

        let version = with-mount {|new, old|
            cd ($dropbear.BUILDAH_WORKING_MOUNTPOINT
               | path join target
               )
            cp -r * $new
            # ./bin/dropbear -V | split row -r '\s+' | last
            # trace o -p 'image-volumes' {dropbear: $version}
        }


        buildah unmount $dropbear.BUILDAH_WORKING_CONTAINER
    }
}
