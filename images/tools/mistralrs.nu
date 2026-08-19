use ../../bx *

export def main [context: record = {}] {
    {
        from: $'($context.image):latest'
        user: master
        workdir: /home/master
    }
    | merge $context
    | build {|ctx|
        let r = { from: $'($context.image):rust' }
        | build --no-commit {|ctx|
            b exec ['cargo install mistralrs-cli']
        }

        b with-mount {|new, old|
            cd $r.BUILDAH_WORKING_MOUNTPOINT
            cp opt/cargo/bin/mistralrs ($new | path join usr/local/bin)
        }

        buildah unmount $r.BUILDAH_WORKING_CONTAINER
    }
}
