use ../../bx *

export def main [context: record = {}] {
    {
        from: $'($context.image):rust'
        user: master
        workdir: /home/master
    }
    | merge $context
    | build {|ctx|
        b conf path [$"/home/($ctx.user)/.moon/bin:$PATH"]
        let url = 'https://cli.moonbitlang.com/install/unix.sh'
        b exec [
            $"curl --retry 3 -fsSL ($url) | sudo -u ($ctx.user) bash"
        ]
    }
}
