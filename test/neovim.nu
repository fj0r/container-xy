use ../bx *

export def --env main [context: record = {}] {
    { from: 'scratch' }
    | build --no-commit --expose {|ctx|
        let nvim = { from: 'ghcr.io/orbsh/xy:latest' }
        | build --no-commit {|ctx|
            pkg install [
                base-devel
                curl jq ca-certificates
                git
            ]
            let version = curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest | from json | get tag_name
            trace o -p neovim-version $version
            let url = $"https://github.com/neovim/neovim/releases/download/($version)/nvim-linux-x86_64.tar.gz"
            b with-mount {|new, old|
                mkdir target
                cd target
                let target = pwd
                trace o -p download $url
                curl -fsSL $url | tar -zxf - -C . --strip-components=1
                mkdir etc
            }
            trace o -p setup-extensions
            let gurl = 'https://github.com/orbsh/nvim-lua.git'
            trace o -p config $gurl
            b exec [
                'cd ~/.config'
                $'git clone --depth=3 ($gurl) nvim'
                '/target/bin/nvim --headless "+Lazy! sync" +qa'
                'rm -rf nvim/lazy/packages/*/.git'
                'mv nvim /target/etc'
            ]
        }

        let version = with-mount {|new, old|
            cd ($nvim.BUILDAH_WORKING_MOUNTPOINT | path join target)
            cp -r * $new
        }
    }
}

def x [] {
    let f = '~/Downloads/nvim-linux-x86_64.tar.gz' | path expand
    if ($f | path exists) {
      cat $f | tar zxf - -C . --strip-component=1
    } else {
        let version = curl -fsSL https://api.github.com/repos/neovim/neovim/releases/latest | from json | get tag_name
        let url = $"https://github.com/neovim/neovim/releases/download/($version)/nvim-linux-x86_64.tar.gz"
        curl -fsSL $url | tar -zxf - -C . --strip-components=1
    }
    mkdir etc
    git clone --depth=1 https://github.com/orbsh/nvim-lua.git etc/nvim
    bin/nvim -u etc/nvim/init.lua --headless "+Lazy! sync" +qa
    rm -rf etc/nvim/lazy/packages/*/.git
}
