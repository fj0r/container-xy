use b.nu
use hub.nu
use rust.nu
use utils.nu *
use history.nu [add-history]



export def install [
    pkgs: list<string> = []
    --stack(-s): list<string> = []
] {
    let pkgs = resolve-stack [stacks $env.OS_RELEASE_ID] $stack $pkgs | str join ' '
    add-history $"install: ($pkgs | str join ' ')"
    match $env.OS_RELEASE_ID {
        arch => {
            b exec [
                $"pacman -Sy --noconfirm ($pkgs)"
                "rm -rf /var/cache/pacman/pkg/*"
            ]
        }
        debian => {
            b exec [
                'apt-get update'
                $'DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ($pkgs)'
                'apt-get autoremove -y'
                'apt-get clean -y'
                'rm -rf /var/lib/apt/lists/*'
            ]
        }
    }
}

export def with [
    pkgs: list<string>
    act
    --stack(-s): list<string> = []
] {
    let pkgs = resolve-stack [stacks $env.OS_RELEASE_ID] $stack $pkgs | str join ' '
    match $env.OS_RELEASE_ID {
        arch => {
            b exec [
                $"pacman -Sy --noconfirm ($pkgs)"
            ]
        }
        debian => {
            b exec [
                'apt-get update'
                $'DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ($pkgs)'
            ]
        }
    }

    if 'rustup' in $pkgs {
        rust up root stable
    }

    let r = do $act

    if 'rustup' in $pkgs {
        b exec [
            'rustup toolchain uninstall $(rustup toolchain list)'
            'rm -rf ~/.rustup/toolchains/*'
            'rm -rf ~/.rustup/downloads/*'
            'rm -rf ~/.cargo/registry/*'
            'rm -rf ~/.cargo/git/*'
        ]
    }

    match $env.OS_RELEASE_ID {
        arch => {
            b exec [
                $"pacman -Rsn --noconfirm ($pkgs)"
                "rm -rf /var/cache/pacman/pkg/*"
            ]
        }
        debian => {
            b exec [
                $'apt-get purge -y --auto-remove ($pkgs)'
                'apt-get clean -y'
                'rm -rf /var/lib/apt/lists/*'
            ]
        }
    }
    $r
}

export def refresh [] {
    match $env.OS_RELEASE_ID {
        arch => {
            b exec ["pacman -Syu --noconfirm"]
        }
        debian => {
            b exec [
                'apt-get update'
                'apt-get upgrade -y'
            ]
        }
    }
}

export def 'py install' [
    pkgs: list<string> = []
    --index-url: string
    --stack(-s): list<string> = []
] {
    let pkgs = resolve-stack [stacks python] $stack $pkgs
    if ($pkgs | is-empty) { return }
    add-history $"py install: ($pkgs | str join ' ')"

    let pip = match $env.OS_RELEASE_ID {
        debian => "pip3"
        _ => "pip",
    }
    mut cmd = [$pip install --no-cache-dir --break-system-packages --ignore-installed]
    if ($index_url | is-not-empty) {
        $cmd ++= [--index-url $index_url]
    }
    $cmd ++= $pkgs
    b exec [ ($cmd | str join ' ') ]
}

export def 'setup py' [
    pkgs: list<string> = []
    --stack(-s): list<string> = []
] {
    let bin = match $env.OS_RELEASE_ID {
        debian => [ python3 python3-pip ],
        _ => [ python python-pip ],
    }
    b conf env {
        PYTHONUNBUFFERED: x
    }
    install $bin
    py install --stack $stack $pkgs
}


export def 'js install' [
    pkgs: list<string> = []
    --runtime: string = 'bun'
    --stack(-s): list<string> = []
] {
    let pkgs = resolve-stack [stacks js] $stack $pkgs
    if ($pkgs | is-empty) { return }
    add-history $"js install: ($pkgs | str join ' ')"

    match $runtime {
        node => {
            b exec [
                $'npm install --global ($pkgs | str join " ")'
                'npm cache clean --force'
            ]
        }
        bun => {
            b exec [
                $'bun install --global --no-cache ($pkgs | str join " ")'
            ]
        }
    }
}

export def 'setup js' [
    pkgs: list<string> = []
    --runtime: string = 'bun'
    --stack(-s): list<string> = []
] {
    match $runtime {
        node => {
            let bin = match $env.OS_RELEASE_ID {
                debian => [ nodejs npm ],
                _ => [ nodejs npm ],
            }
            install $bin
        }
        bun => {
            hub install [bun]
            b exec [
                'cd /usr/local/bin'
                'ln -s bun node'
            ]
            b conf env {
                BUN_INSTALL_BIN: "/usr/local/bin"
                BUN_NODE_ALIASES: "1"
            }
        }
    }
    js install --runtime $runtime --stack $stack $pkgs
}
