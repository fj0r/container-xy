use ../../bx *

export def main [context: record = {}] {
    $context
    | update image {|x|
        $x.image | path split | slice ..-2 | append 'assets' | path join
    }
    | merge {
        from: scratch
        tag: 'boringtun'
    }
    | build {|ctx|
        let boringtun = { from: rust }
        | build --no-commit {|ctx|
            b exec [
                'mkdir /target'
                'cargo install --locked boringtun-cli'
                "bin_file=$(whereis boringtun-cli | awk '{print $2}')"
                'strip -s $bin_file'
                'cp $bin_file /target'
            ]
        }

        let version = b with-mount {
            mkdir bin
            cp ($boringtun.BUILDAH_WORKING_MOUNTPOINT
               | path join target boringtun-cli
               ) bin
            # ./bin/boringtun-cli | split row -r '\s+' | last
            # trace o -p 'image-volumes' {boringtun: $version}
        }

        buildah unmount $boringtun.BUILDAH_WORKING_CONTAINER
    }
}
