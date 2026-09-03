use ../../bx *

export def main [context: record = {}] {
    {
        from: $'($context.image):deb'
        user: master
        workdir: /srv
        tag: ferron
    }
    | merge $context
    | build {|ctx|
        b conf expose [8080]
        hub install [ferron] -c $ctx.cache?

        b with-mount {|new, old|
            r#'
            *:8080 {
                root "/srv"
            }
            '#
            | str trim
            | str replace -rma $'^ {12}' ''
            | save etc/ferron.conf
        }

        b with-mount {
            cd entrypoint
            r#'
            #!/usr/bin/env nu
            use libs/tasks.nu

            let cmd = [
                /usr/local/bin/ferron
                run
                --config
                ($env.CONFIGFILE? | default /etc/ferron.conf)
            ]

            tasks spawn {
                tag: ferron
                msg: ($cmd | str join " ")
                cmd: $cmd
            }
            '#
            | str trim
            | str replace -rma $'^ {12}' ''
            | save ferron.nu
        }

        b with-mount {
            cd srv
            mkdir ferron bin data hooks meta
        }

        b copy images/service/ferron /srv/ferron

        b conf env {
            CONFIGFILE: /srv/ferron/box.conf
        }

        b conf workdir $ctx.workdir
        b conf cmd ['srv']
    }
}
