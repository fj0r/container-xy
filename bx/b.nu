use trace.nu
use history.nu [consume-history add-history]

export def copy [src dst] {
    trace inc-level
    trace o copy $src $dst
    add-history $"copy: ($src) -> ($dst)"
    buildah copy $env.BUILDAH_WORKING_CONTAINER $src $dst
}

export def exec [cmd: list --with-nu] {
    trace inc-level
    if $with_nu {
        add-history $"nu -c: ($cmd)"
        let cmd = $cmd | str join (char newline) | trace f run-with-nu
        buildah run $env.BUILDAH_WORKING_CONTAINER nu -c $cmd
    } else {
        add-history $"bash -c: ($cmd)"
        let cmd = $cmd | str join ' && ' | trace f run
        buildah run $env.BUILDAH_WORKING_CONTAINER bash -c $cmd
    }
}

export def commit [image] {
    trace o -p commit $image
    let msg = consume-history
    buildah config --add-history --history-comment $msg $env.BUILDAH_WORKING_CONTAINER
    buildah commit --format docker --rm $env.BUILDAH_WORKING_CONTAINER $image
    rm -f $env.BUILDAH_WORKING_HISTORY
}

export def with-mount [act] {
    trace inc-level
    let tg = $env.BUILDAH_WORKING_MOUNTPOINT
    let old = $env.PWD
    cd $tg
    trace o -p with-mount $tg
    add-history "mount"
    do $act $tg $old
    add-history "unmount"
}

export module conf {
    export def env [d: record] {
        trace inc-level
        if 'PATH' in $d { error make { msg: 'set PATH via `conf path`'} }
        $d
        | trace f config env
        | items {|k, v| [--env ($k)=($v)] }
        | flatten
        | buildah config ...$in $env.BUILDAH_WORKING_CONTAINER
    }

    export def path [v: list] {
        trace inc-level
        $v
        | append ['$PATH']
        | str join ':'
        | buildah config --env PATH=($in) $env.BUILDAH_WORKING_CONTAINER
    }

    export def expose [v: list] {
        trace inc-level
        $v
        | trace f config expose
        | each {|x|
            let x = $x | into string
            if ($x | str starts-with u) {
                [--port ($x | str substring 1..)/udp]
            } else {
                [--port ($x)/tcp]
            }
        }
        | flatten
        | buildah config ...$in $env.BUILDAH_WORKING_CONTAINER
    }

    export def volume [v: list] {
        trace inc-level
        $v
        | trace f config volume
        | each {|x| [--volume $x] }
        | flatten
        | buildah config ...$in $env.BUILDAH_WORKING_CONTAINER
    }

    export def workdir [path] {
        trace inc-level
        $path
        | trace f config workdir
        | do {|x| [--workingdir $x] } $in
        | buildah config ...$in $env.BUILDAH_WORKING_CONTAINER
    }

    export def entrypoint [v: list] {
        trace inc-level
        $v
        | trace f config entrypoint
        | to json -r
        | buildah config --entrypoint $in $env.BUILDAH_WORKING_CONTAINER
    }

    export def cmd [v: list] {
        trace inc-level
        $v
        | trace f config cmd
        | to json -r
        | buildah config --cmd $in $env.BUILDAH_WORKING_CONTAINER
    }

    export def user [name] {
        buildah config --user $name $env.BUILDAH_WORKING_CONTAINER
    }
}
export use conf
