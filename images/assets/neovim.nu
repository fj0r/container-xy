use ../../bx *

export def main [context: record = {}] {
    $context
    | update image {|x|
        $x.image | path split | slice ..-2 | append 'assets' | path join
    }
    | merge {
        from: scratch
        tag: 'nvim'
    }
    | build {|ctx|
        let nvim = { from: $'($context.image):deb' }
        | build --no-commit {|ctx|
            pkg install [
                build-essential
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

        buildah unmount $nvim.BUILDAH_WORKING_CONTAINER
    }
}
