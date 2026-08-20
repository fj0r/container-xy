use ../../bx *

export def main [context: record = {}] {
    {
        from: $'($context.image):deb'
        user: master
        workdir: /data
        tag: headscale
    }
    | merge $context
    | build {|ctx|
        pkg install [ca-certificates]
        hub install [headscale] -c $ctx.cache?

        b conf expose [8080]

        b with-mount {
            r#'
            #!/usr/bin/env nu
            use libs/tasks.nu

            # ------------------------------------------------------------------
            # Headscale: a self-hostable coordinate server for Tailscale clients.
            # TLS is terminated upstream by the gateway (this container only
            # listens plaintext HTTP on 8080, reverse-proxied as https://host).
            #
            # HS_SERVER_URL -> public base URL clients reach the server at,
            #                  e.g. https://hs.example.com  (no default: required)
            # HS_DATA       -> directory for config.yaml + state (default /data)
            # ------------------------------------------------------------------

            let data = ($env.HS_DATA? | default "/data")
            let server_url = $env.HS_SERVER_URL?
            if ($server_url | is-empty) {
                error make { msg: "HS_SERVER_URL is required, e.g. https://hs.example.com" }
            }

            mkdir $data
            let cfg = ($data | path join config.yaml)

            if not ($cfg | path exists) {
                let yaml = $'
                    server_url: ($server_url)

                    listen_addr: 0.0.0.0:8080
                    metrics_listen_addr: 127.0.0.1:9090

                    noise:
                      private_key_path: ($data)/noise_private.key

                    prefixes:
                      v4: [100.64.0.0/10]
                      v6: [fd7a:115c:a1e0::/48]

                    # no OIDC by default (only activated by setting oidc.issuer):
                    # users are created locally via `headscale users create`,
                    # and nodes enroll via pre-authenticated keys (`preauthkeys create`).
                    magic_dns: false
                    dns:
                      base_domain: example.com

                    database:
                      type: sqlite
                      sqlite:
                        path: ($data)/headscale.db
                '
                $yaml | str trim | save $cfg
                print $"Generated headscale config: ($cfg)"
                print $"server_url = ($server_url)"
            }

            tasks spawn {
                tag: headscale
                msg: $"Starting headscale: ($cfg)"
                cmd: [
                    /usr/local/bin/headscale
                    serve
                    -c $cfg
                ]
            }
            '#
            | str trim
            | str replace -rma $'^ {12}' ''
            | save entrypoint/headscale.nu
        }

        b conf workdir $ctx.workdir
        b conf cmd ['srv']
    }
}