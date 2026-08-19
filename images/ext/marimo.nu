use ../../bx *

export def main [context: record = {}] {
    {
        from: $'($context.image):latest'
        user: master
        workdir: /home/master
    }
    | merge $context
    | build {|ctx|
        b conf expose [8080]
        b conf env {
            HOST: '0.0.0.0'
            PORT: '8080'
        }
        pkg with [ base-devel ] {
            pkg py install [
                boto3 lancedb duckdb
                numpy scikit-learn polars[all]
                marimo[recommended,lsp,sql] altair
            ]
            pkg py install --index-url https://download.pytorch.org/whl/cpu [
                torch torchvision torchaudio
            ]
        }
        b with-mount {
            cd entrypoint
            r#'
            #!/usr/bin/env nu
            use libs/tasks.nu

            tasks spawn {
                tag: marimo
                msg: "Starting marimo."
                cmd: [
                    marimo
                    edit --no-token
                    -p $env.PORT
                    --host $env.HOST
                ]
            }
            '#
            | str trim
            | str replace -rma $'^ {12}' ''
            | save marimo.nu
        }
        b conf cmd ['srv']
        b conf user master
    }
}
