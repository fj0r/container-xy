use ../../bx *


export def main [context: record = {}] {
    {
        from: $'($context.image):latest'
        user: master
        workdir: /home/master
    }
    | merge $context
    | merge { tag: playwright }
    | build {|ctx|
        pkg py install [playwright]
        b exec ['playwright install chromium']
    }
}
