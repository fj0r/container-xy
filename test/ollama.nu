use ../bx *

export def main [context: record = {}] {
    {
        from: 'ghcr.io/orbsh/xy:ollama'
        author: unnamed
        timezone: Asia/Shanghai
        user: master
        workdir: /home/master
        image: test
        tag: ollama
    }
    | merge $context
    | build {|ctx|
        b conf cmd [srv]
        b exec ['ollama --version']
        b with-mount {
            cd entrypoint
            r#'
            #!/usr/bin/env nu
            use libs/tasks.nu

            def run-ollama [model?] {
                let act = if $env.ENTRYPOINT_ARGS?.0? == 'srv' {
                    ['serve']
                } else {
                    $env.ENTRYPOINT_ARGS
                }
                tasks spawn {
                    tag: ollama
                    cmd: [/bin/ollama ...$act]
                }
            }

            run-ollama $env.MODEL_PATH?
            '#
            | str trim
            | str replace -rma $'^ {12}' ''
            | save -f ollama.nu
        }
    }
}
