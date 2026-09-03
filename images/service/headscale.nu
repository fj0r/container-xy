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

        b conf expose [8080 u3478]

        b with-mount {
            r#'
            #!/usr/bin/env nu
            use libs/tasks.nu

            # ------------------------------------------------------------------
            # Headscale: a self-hostable coordinate server for Tailscale clients.
            # TLS is terminated upstream by the gateway (this container only
            # listens plaintext HTTP on 8080, reverse-proxied as https://host).
            #
            # HS_SERVER_URL        -> public base URL clients reach the server
            #                          at, e.g. https://hs.example.com (required)
            # HS_DATA              -> directory for config.yaml + state
            #                          (default /data)
            # HS_MAGIC_DNS         -> "true" enables MagicDNS (default false)
            # HS_DNS_BASE_DOMAIN   -> dns.base_domain (default example.com)
            # HS_DNS_NAMESERVERS   -> comma-separated global nameservers
            #                          (empty = omit global resolvers)
            # HS_PREFIX_V4/V6      -> prefixes.v4 / prefixes.v6
            # HS_PREFIX_ALLOCATION -> prefixes.allocation (empty = omit)
            # HS_DERP_REGION_CODE  -> embedded DERP region_code (default cn)
            # HS_DERP_REGION_NAME  -> embedded DERP region_name
            # HS_STUN_PORT         -> embedded DERP STUN listen port
            #                          (default 3478)
            # HS_LOG_LEVEL         -> log.level (empty = omit)
            # HS_EPHEMERAL_INACTIVITY_TIMEOUT
            #                      -> node.ephemeral.inactivity_timeout
            #                         (empty = omit ephemeral nodes)
            # ------------------------------------------------------------------

            let data = ($env.HS_DATA? | default "/data")
            let server_url = $env.HS_SERVER_URL?
            if ($server_url | is-empty) {
                error make { msg: "HS_SERVER_URL is required, e.g. https://hs.example.com" }
            }

            mkdir $data
            let cfg = ($data | path join config.yaml)

            if not ($cfg | path exists) {
                let magic_dns = (($env.HS_MAGIC_DNS? | default "false") == "true")
                let base_domain = ($env.HS_DNS_BASE_DOMAIN? | default "example.com")
                let nameservers = ($env.HS_DNS_NAMESERVERS?
                    | default ""
                    | split row ","
                    | str trim
                    | where {|x| $x != ""})

                mut dns = {
                    magic_dns: $magic_dns
                    base_domain: $base_domain
                }
                if ($nameservers | is-not-empty) {
                    $dns = ($dns | insert nameservers { global: $nameservers })
                } else {
                    # 0.29: override_local_dns defaults to true and then
                    # requires nameservers.global — opt out instead
                    $dns = ($dns | insert override_local_dns false)
                }

                # null allocation would serialize as `allocation: null`,
                # rebuild prefixes without the key when unset
                mut prefixes = {
                    v4: ($env.HS_PREFIX_V4? | default "100.64.0.0/10")
                    v6: ($env.HS_PREFIX_V6? | default "fd7a:115c:a1e0::/48")
                }
                let allocation = ($env.HS_PREFIX_ALLOCATION?)
                if ($allocation | is-not-empty) {
                    $prefixes = ($prefixes | insert allocation $allocation)
                }

                mut config = {
                    server_url: $server_url

                    listen_addr: "0.0.0.0:8080"
                    metrics_listen_addr: "127.0.0.1:9090"

                    noise: {
                        private_key_path: $"($data)/noise_private.key"
                    }

                    prefixes: $prefixes

                    # no OIDC by default (only activated by setting oidc.issuer):
                    # users are created locally via `headscale users create`,
                    # and nodes enroll via pre-authenticated keys
                    # (`preauthkeys create`).

                    # Embedded DERP relay. Protocol lives on the main HTTP
                    # router under /derp and uses cfg.server_url, so it is
                    # reverse-proxied by the gateway along with the control
                    # plane — no extra HTTP port, no self-managed TLS.
                    # Omit derp.urls / auto_update: with the embedded region
                    # auto-added, the map is non-empty; clients relay only
                    # through our own region (no public Tailscale DERP map).
                    derp: {
                        server: {
                            enabled: true
                            region_id: 999
                            region_code: ($env.HS_DERP_REGION_CODE? | default "cn")
                            region_name: ($env.HS_DERP_REGION_NAME? | default "Headscale cn DERP")
                            private_key_path: $"($data)/derp_server_private.key"
                            verify_clients: true
                            stun_listen_addr: $"0.0.0.0:($env.HS_STUN_PORT? | default 3478)"
                        }
                    }

                    database: {
                        type: sqlite
                        sqlite: {
                            path: $"($data)/headscale.db"
                        }
                    }

                    dns: $dns
                }


                let log_level = ($env.HS_LOG_LEVEL?)
                if ($log_level | is-not-empty) {
                    $config = ($config | insert log { level: $log_level })
                }

                let ephemeral = ($env.HS_EPHEMERAL_INACTIVITY_TIMEOUT?)
                if ($ephemeral | is-not-empty) {
                    $config = ($config | insert node {
                        ephemeral: { inactivity_timeout: $ephemeral }
                    })
                }

                $config | to yaml | save $cfg
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
