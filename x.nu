const CWD = path self .
const CFG = path self x.toml
const NU_LIB_DIRS = ['($CWD)']

export module hub {
    def cmpl-version [] {
        open ($CWD | path join hub.yaml)
        | get packages
        | columns
    }

    export def version [
        hub?:string@cmpl-version
        --repo(-r):string
    ] {
        use bx/hub.nu
        $env.BX_DATADIR = $CWD
        if ($repo | is-not-empty) {
            hub get-version { repo: $repo }
        } else {
            hub get-version (open hub.yaml | get packages | get $hub)
        }
    }
}
export use hub

export module action {
    export def update-nu-version [] {
        use hub
        let version = hub version nushell
        for f in (ls .github/workflows/* | get name) {
            let txt = open -r $f | lines
            let occ = $txt
            | enumerate
            | where {|x| $x.item | find 'setup-nu' | is-not-empty }
            | first
            | get index?
            if ($occ | is-not-empty) {
                $txt
                | enumerate
                | each {|x|
                    if $x.index == $occ + 2 {
                        let r = $x.item
                        | parse -r  "^(?<t>.*version: )(?<v>.+)"
                        | first
                        $"($r.t)($version)"
                    } else {
                        $x.item
                    }
                }
                | append ''
                | str join (char newline)
                | save -f $f
            }
        }
    }

    export def gen [
        --reg:string = "ghcr.io"
        --user:string = "orbsh"
        --image:string = xy
    ] {
        use hub
        let nu_ver = hub version nushell
        cd ($CWD | path join images)
        let fs = ls */*.nu
        | get name
        | where { not ($in | str starts-with test/) }
        | each { $in | path parse }
        for f in $fs {
            {
                name: branch_($f.stem),
                on: {
                    push: {
                        branches: [ $f.stem ],
                        tags: [ "v*.*.*" ]
                    },
                    workflow_dispatch: null
                },
                env: { REGISTRY: $reg, USERNAME: $user, IMAGE_NAME: $image },
                jobs: {
                    build: {
                        runs-on: ubuntu-latest,
                        if: "${{ !endsWith(github.event.head_commit.message, '~') }}",
                        permissions: {
                            contents: read,
                            packages: write
                        },
                        steps: [
                            {
                                name: "Checkout repository",
                                uses: "actions/checkout@v3",
                                with: {
                                    submodules: "true"
                                }
                            },
                            {
                                name: "Log into registry ${{ env.REGISTRY }}",
                                if: "github.event_name != 'pull_request'",
                                uses: "docker/login-action@v2",
                                with: {
                                    registry: "${{ env.REGISTRY }}",
                                    username: "${{ env.USERNAME }}",
                                    password: "${{ secrets.GHCR_TOKEN }}"
                                }
                            },
                            {
                                name: "Extract Docker metadata",
                                id: meta,
                                uses: "docker/metadata-action@v4",
                                with: {
                                    images: "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}"
                                }
                            },
                            {
                                name: "Setup Nushell",
                                uses: "hustcer/setup-nu@v3",
                                with: {
                                    version: $nu_ver
                                }
                            },
                            # {
                            #     name: "Setup upterm session",
                            #     uses: "owenthereal/action-upterm@v1",
                            #     if: "contains(github.event.head_commit.message, '+debug')",
                            #     with: {
                            #         upterm-server: "${{ secrets.UPTERMD_ADDR }}"
                            #     }
                            # },
                            {
                                name: $"build ($f.stem)",
                                shell: "buildah unshare nu {0}",
                                run: (
                                    $"
                                    overlay use ${{ github.workspace }}/images/($f.parent)/($f.stem).nu as build
                                    build {
                                      author: ${{ env.USERNAME }}
                                      password: ${{ secrets.GHCR_TOKEN }}
                                      image: ${{ env.REGISTRY }}/${{ env.USERNAME }}/${{ env.IMAGE_NAME }}
                                      tag: ($f.stem)
                                    }
                                    "
                                    | str trim
                                    | str replace -rma '^ {36}' ''
                                    )
                            },
                            {
                                name: "Delete untagged ghcr",
                                uses: "Chizkiyahu/delete-untagged-ghcr-action@v3",
                                with: {
                                    token: "${{ secrets.GHCR_TOKEN }}",
                                    repository: "${{ github.repository }}",
                                    repository_owner: "${{ github.repository_owner }}",
                                    package_name: "",
                                    untagged_only: true,
                                    except_untagged_multiplatform: false,
                                    owner_type: user
                                }
                            }
                        ]
                    }
                }
            }
            | save -f ($CWD)/.github/workflows/branch_($f.stem).yaml
        }
    }
}
export use action

export module image {
    def cmpl-tags [] {
        open $CFG | get assets.image.manifest | columns | { completions: $in, options: { sort: false } }
    }

    export def pull [
        ...tags:string@cmpl-tags
        --archive
    ] {
        use bx/trace.nu
        let cfg = open $CFG | get assets.image
        let s = $cfg.manifest | transpose k v
        let s = if ($tags | is-empty) { $s } else { $s | where {|i| $i.k in $tags } }
        for i in $s {
            mut images = []
            for j in ($i.v | transpose k v) {
                for t in $j.v {
                    let img = ($cfg.repo)/($j.k):($t)
                    trace o pull $img
                    ^$env.CNTRCTL pull $img
                    let short = ($j.k):($t)
                    notify-send $short
                    $images ++= [$short]
                    trace o move $short
                    ^$env.CNTRCTL tag $img $short
                    ^$env.CNTRCTL rmi $img
                }
            }
            if $archive {
                trace o begin archive $images
                ^$env.CNTRCTL save ...$images | zstd -18 -T0
                | save -pf  $"($cfg.dest)/($i.k).tar.zst"
                trace o end archive
            }
        }
    }
}
export use image

def cmpl-build [] {
    glob ($CWD)/test/*.nu
    | append (glob ($CWD)/images/*/*.nu)
    | path relative-to $CWD
}

export def build [s: string@cmpl-build] {
    buildah unshare nu -c $"
        const NU_LIB_DIRS = ['($CWD)']
        overlay use ($s) as build
        build {
            cache: ~/Downloads
            image: xy
            author: orbit
            skip_push: true
        }
        "
        | str trim
        | str replace -rma '^ {12}' ''
}

export module test {
    def cmpl-ferron [] {
        glob ($CWD)/images/service/ferron/*.conf
        | path parse
        | get stem
    }

    export def box [
        config:string@cmpl-ferron
        --ssh(-s)
        --image(-i): string = 'xy:box'
    ] {
        let name = 'test-box'
        ^$env.CNTRCTL rm -f $name
        mut flag = [
            -it
            --name $name
            -v ($CWD)/images/service/ferron:/srv/ferron
            -v ($CWD)/entrypoint/libs:/entrypoint/libs
            -e CONFIGFILE=/srv/ferron/($config).conf
            -p 9900:8080
        ]
        if $ssh {
            $flag ++= [
                -e SSH_HOSTKEY_ED25519=AAAAC3NzaC1lZDI1NTE5AAAAQNX1odF2vYCSKM1jjij7nxZgikenc2NmzPn+60QIuVBJctmdoUdXGLWexsg4QfyJkwdA9igQEHPzUoBxbSvr15c=
                -e SSH_SUDO_GROUP=wheel
                -e ed25519_root=AAAAC3NzaC1lZDI1NTE5AAAAIK2Q46WeaBZ9aBkS3TF2n9laj1spUkpux/zObmliHUOI
                -p 2266:22
                -p 2311:2311
            ]
        }
        ^$env.CNTRCTL run ...$flag $image
    }

    export def hooks [
        hook: path = scripts/hook_x.nu
        payload: path = scripts/hook_x.nu
        --path: string = ''
    ] {
        curl -sSL --progress-bar -X PUT -T $hook $"localhost:9900/box/__hooks__/($path)($payload)"
        curl -sSL --progress-bar -X PUT -T $payload $"localhost:9900/box/($path)($payload)"
        curl -sSL --progress-bar -X PUT -T $hook $"localhost:9900/box/__hooks__/a/b/c/__"
        curl -sSL --progress-bar -X PUT -T $hook localhost:9900/box/a/b/c/d/e/f/g/h/i/j/k
    }

    export def exec [
        --user(-u)
        --socat
        --s3
        --ssh
        --bash
        --image(-i): string = 'xy:rust'
        --check: duration = 1sec
        ...args
    ] {
        let name = 'test-xy'
        ^$env.CNTRCTL rm -f $name
        mut flag = [
            -it
            --name $name
            --device /dev/fuse --privileged
            -v ($CWD)/entrypoint/libs:/entrypoint/libs
            # -v ($CWD)/entrypoint:/entrypoint
            --entrypoint /entrypoint/libs/init.nu
            -e CHECK_INTERVAL=($check)
        ]
        if $bash {
            $flag ++= [-e SPAWN_VIA_BASH=1]
        }
        if $user {
            $flag ++= [--user 1000]
        }
        if $ssh {
            $flag ++= [
                -e SSH_HOSTKEY_ED25519=AAAAC3NzaC1lZDI1NTE5AAAAQNX1odF2vYCSKM1jjij7nxZgikenc2NmzPn+60QIuVBJctmdoUdXGLWexsg4QfyJkwdA9igQEHPzUoBxbSvr15c=
                -e SSH_SUDO_GROUP=wheel
                -p 2266:22
                -p 2311:2311
            ]
            if $user {
                $flag ++= [-e ed25519_master=AAAAC3NzaC1lZDI1NTE5AAAAIK2Q46WeaBZ9aBkS3TF2n9laj1spUkpux/zObmliHUOI]
            } else {
                $flag ++= [-e ed25519_root=AAAAC3NzaC1lZDI1NTE5AAAAIK2Q46WeaBZ9aBkS3TF2n9laj1spUkpux/zObmliHUOI]
            }
        }
        if $s3 {
            $flag ++= [
                -e 's3_pre=/srv/att,root,http://x.com,oss,test,access,secrets,nonempty'
                -e 's3_dev=/srv/att,root,http://x.com,oss,test,access,secrets,nonempty'
            ]
        }
        if $socat {
            $flag ++= [
                -e tcp_123=abc:123
                -e tcp_456=abc:456
                -e udp_123=uuu:123
                -e udp_456=uuu:456
            ]
        }
        ^$env.CNTRCTL run ...$flag $image ...$args
    }

    export def hermes [
        ...args
    ] {
        let image = 'ghcr.io/orbsh/xy:hermes'
        mut flag = [
            -e DASHSCOPE_API_KEY=(asn --all | get api_key)
            -v ($env.PWD)/images/tools/entrypoint/hermes.nu:/entrypoint/hermes.nu
        ]
        ^$env.CNTRCTL run ...$flag $image ...$args
    }

    export def zeroclaw [
        ...args
    ] {
        let image = 'ghcr.io/orbsh/xy:zeroclaw'
        mut flag = [
            -p 42617:42617
            -e API_KEY=(asn --all | get api_key)
        ]
        $flag ++= [-v ($env.PWD)/images/tools/entrypoint/zeroclaw.nu:/entrypoint/zeroclaw.nu]
        $flag ++= (open ~/.config/mattermost_bot.yaml | items {|k, v| [-e ($k)=($v)]} | flatten)

        ^$env.CNTRCTL run ...$flag $image ...$args
    }

    export def openclaw [
        ...$args
        --image(-i): string = 'xy:openclawx'
        --init
        --proxy
    ] {
        let cnm = 'test-openclaw'
        do -i { dcr $cnm }
        mut flag = [
            --name $cnm
            -p 18789:18789
            -e QWEN_API_KEY=(asn --all | get api_key)
            -e QWEN_MODEL=glm-5
            -e SKILL_PACKAGE_URLS=http://file.s/kb.tar.zst
        ]
        if not $init {
            $flag ++= [-v ($env.HOME)/.openclaw:/app/data]
        }
        if $proxy {
            $flag ++= [-e PROXY=socks5://host.docker.internal:8989]
        }
        ^$env.CNTRCTL run ...$flag $image ...$args
    }

    export def openfang [
        --image(-i): string = 'ghcr.io/orbsh/xy:openfang'
    ] {
        mut flag = [
            --name test-openfang
            -p 4200:4200
            -v ($env.HOME)/.openfang:/root/.openfang
        ]
        for i in (open ~/.config/openfang.yaml | transpose k v) {
            $flag ++= [-e $"($i.k)=($i.v)"]
        }
        ^$env.CNTRCTL run ...$flag $image
     }

}
export use test  

