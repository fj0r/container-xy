use trace.nu
use build.nu
use transformer.nu
use extract.nu
use b.nu
use utils.nu *
use history.nu [add-history]

export def get-version [cfg]: nothing -> string {
    trace inc-level
    if $cfg.type? in ['ImageVolume'] {
        return ''
    }
    let CACHE = $env.BX_DATADIR | path join version.yaml
    if ($CACHE | path exists) {
        let f = open $CACHE
        if $cfg.repo? in $f {
            let ver = $f | get $cfg.repo
            trace o -p 'version' { repo: ($cfg.repo? | default {$cfg.type}), version: $ver, cache: true }
            return $ver
        }
    } else {
        {} | to yaml | save $CACHE
    }
    let ver = if ($cfg.repo | str starts-with 'http') {
        curl --retry 3 -fsSL $cfg.repo
    } else if ($cfg.list_tags? | default false) {
        let url = $"https://api.github.com/repos/($cfg.repo)/releases"
        curl --retry 3 -fsSL $url | from json
    } else {
        let url = $"https://api.github.com/repos/($cfg.repo)/releases/latest"
        curl --retry 3 -fsSL $url | from json | get tag_name
    }
    trace o -p 'version' { repo: ($cfg.repo? | default {$cfg.type}), version: $ver }
    let v = $ver | transformer run $cfg.version?
    open $CACHE | upsert $cfg.repo $v | to yaml | save -f $CACHE
    $v
}

export def format-uri [cfg]: record -> list<string> {
    let vers = $in
    let uris = if ($cfg.uri | describe -d).type == list {
        $cfg.uri
    } else {
        [$cfg.uri]
    }

    $uris
    | each {|x|
        let u = $vers | format pattern $x
        if $cfg.type? in ['ImageVolume'] {
            $u
        } else if ($u | str starts-with 'http') {
            $u
        } else {
            $'https://github.com/($cfg.repo)/releases' | path join $u
        }
    }
}

def arch2 [a] {
    match $a {
        'x86_64' => 'amd64',
        'aarch64' => 'arm64',
        'i386' | 'i686' => '396',
        'armv7' | 'armhf' => 'arm'
        _ => $a
    }
}

def arch3 [a] {
    match $a {
        'x86_64' => 'x64',
        _ => $a
    }
}

export def install [
    pkgs
    --user: string
    --author(-A): string
    --target(-t): string = '/usr/local'
    --option(-o): closure
    --cache(-c): string = ''
    --arch: string
    --bundle
    --with-python
] {
    trace inc-level
    add-history $"hub-install: ($pkgs | str join ' ')"
    for t in $pkgs {
        trace o -p 'hub-install' $t
        (
            install-inner
            $t
            -t $target
            -o $option
            -c $cache
            --bundle=$bundle
            --arch $arch
            --user $user
            -A $author
            --with-python=$with_python
        )
    }
}


def install-inner [
    tag
    --user: string
    --author(-A): string
    --target(-t): string
    --option(-o): closure
    --cache(-c): string
    --arch: string
    --bundle
    --with-python
] {
    trace inc-level
    let cfg = open ($env.BX_DATADIR | path join hub.yaml) | get packages | get $tag
    let arch = if ($arch | is-empty) { $nu.os-info.arch } else { $arch }

    let python_version = if $with_python {
        http get https://www.python.org/downloads/source/
        | grep -oP 'Latest Python 3 Release - Python \K[0-9.]+'
    } else {
        ''
    }

    let pkgv = {
        version: (get-version $cfg)
        arch: $arch
        arch2: (arch2 $arch)
        arch3: (arch3 $arch)
        python_version: $python_version
    }

    let uris = $pkgv | format-uri $cfg

    let origin = pwd

    let wd = mktemp -t -d --suffix .buildah
    cd $wd

    for uri in $uris {
        if $cfg.type? in ['ImageVolume'] {
            let ctx = { from: $uri } | build --no-commit {|ctx| }
            cd ($ctx.BUILDAH_WORKING_MOUNTPOINT | path join $cfg.path)
            cp -r * $wd
            buildah unmount $ctx.BUILDAH_WORKING_CONTAINER
            cd $wd
        } else {
            let f = $uri | url parse | get path | path parse
            let f = [$f.stem $f.extension]
            | where { $in | is-not-empty }
            | str join '.'

            let cache = if ($cache | is-not-empty) {
                ($cache)/($f) | path expand
            }
            if ($cache | is-empty) {
                trace o -p 'fetch' { uri: $uri, file: $f }
                curl --retry 3 -fsSL $uri -o $f
            } else {
                if not ($cache | path exists) {
                    trace o -p 'fetch' { uri: $uri, cache: $cache }
                    curl --retry 3 -fsSL $uri -o $cache
                }
                trace o -p 'use-cache' { uri: $uri, file: $f, cache: $cache }
                cp $cache $f
            }

            let ext = $uri | split row '.' | last 2
            cat $f | extract as $ext $f
        }
    }


    let upk = $cfg.unpack? | default [] | each {|x| $pkgv | format pattern $x}
    let dst = extract unpack $upk | prepend $wd

    trace o -p 'temp-dirs' $dst
    cd ($dst | last)
    trace o -p 'files-ready' $env.PWD
    b with-mount {|new, old|
        let target = relative-path $target
        let new_target = $new | path join $target
        mkdir $new_target
        let d = $new_target | path parse | get parent
        trace o -p 'target' {new_target : $new_target, target: $target, d: $d}
        if not ($d | path exists) {
            trace o -p 'create-dir' $d
            mkdir $d
        }
        cd $old

        let opt = $cfg.options? | default {}
        let opt = if ($option | is-empty) { $opt } else { do $option $opt }
        let envs = {
            options: $opt
            context: $origin
            mount: $new
            target: $target
            workdir: $env.PWD
            user: $user
            author: $author
        }

        $cfg.hooks?.prepare? | run-script HUBHOOK $envs [ trace.nu ]

        if $bundle {
            mkdir ($new_target | path join $arch)
            if ($cfg.hooks?.post? | is-not-empty) {
                $cfg.hooks.post | gen-script HUBHOOK ($envs | merge {
                    context: ''
                    mount: '/'
                    target: 'usr/local'
                    workdir: ''
                }) [ trace.nu ]
                | save -f setup.nu
            }
            # tar --transform='s#^./##' -cvf - .
            tar -cvf - *
            | zstd -18 -T0
            | save -f ($new_target | path join $arch $'($tag).tar.zst')
        } else {
            cp -r * $new_target
            $cfg.hooks?.post? | run-script HUBHOOK $envs [ trace.nu ]
        }

    }

    cd $origin
    for d in ($dst | uniq) {
        trace o -p 'clean-temp-dir' $d
        rm -rf $d
    }
}

export def run-script [
    key: string
    envs: record
    mods: list<string>
]: any -> nothing {
    let input = $in
    if ($input | is-empty) { return }

    trace inc-level
    let ctx = mktemp -d
    trace o -p run-script $ctx

    const self = path self .
    mut $r = []
    for m in $mods {
        let n = $m | path parse | get stem
        let m = open -r ($self | path join $m)
        | str replace -rma '^' '    '
        | $"module ($n) {\n($in)\n}\nuse ($n)"
        $r ++= [$m]
    }
    let m = "
    module b {
        use trace
        export def exec [cmd: list --with-nu] {
            trace inc-level
            if $with_nu {
                $cmd
                | str join (char newline)
                | trace f run-with-nu
                | buildah run $env.BUILDAH_WORKING_CONTAINER nu -c $in
            } else {
                $cmd
                | str join ' && '
                | trace f run
                | buildah run $env.BUILDAH_WORKING_CONTAINER bash -c $in
            }
        }
    }
    use b
    "
    | str trim
    | str replace -rma '^ {4}' ''
    $r ++= [$m]

    $r ++= [$input]

    let main = $ctx | path join main.nu
    $r | str join "\n\n" | save -f $main
    with-env { $key: ($envs | to nuon) } {
        nu $main
    }
    rm -rf $ctx
}

export def gen-script [
    key: string
    envs: record
    mods: list<string>
]: any -> string {
    let input = $in
    if ($input | is-empty) { return }

    mut ctx = []
    trace o -p run-script

    const self = path self .
    for m in $mods {
        let n = $m | path parse | get stem
        let m = open -r ($self | path join $m)
        | str replace -rma '^' '    '
        | $"module ($n) {\n($in)\n}\nuse ($n)"
        $ctx ++= [$m]
    }

    let m = "
    module b {
        use trace
        export def exec [cmd: list --with-nu] {
            if $with_nu {
                $cmd
                | str join (char newline)
                | trace f run-with-nu
                | nu -c $in
            } else {
                $cmd
                | str join ' && '
                | trace f run
                | bash -c $in
            }
        }
    }
    use b
    "
    | str trim
    | str replace -rma '^ {4}' ''
    $ctx ++= [$m]

    let m = $input
    | str replace -rma '^' '    '
    | $"def apply [] {\n($in)\n}"
    $ctx ++= [$m]

    let m = $"
    export def main [ctx] {
        let envs = r#'
        ($envs | to nuon)
        '#
        | from nuon
        | merge \($ctx | from nuon\)
        | to nuon
        with-env { ($key): $envs } {
            apply
        }
    }
    "
    | str replace -rma  '^ {4}' ''
    $ctx ++= [$m]

    $ctx | str join "\n\n"
}

export def sync [arg action] {
    let version = hub get-version $arg.cfg
    let tag = {version: $version} | format pattern $arg.tag
    if ($tag not-in $arg.obj) {
        do $action { version: $version, tag: $tag }
    } else {
        trace o $tag exists
    }
    return $tag
}
