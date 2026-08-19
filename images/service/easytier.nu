use ../../bx *

export def main [context: record = {}] {
    {
        from: $'($context.image):deb'
        user: master
        workdir: /srv
        tag: easytier
    }
    | merge $context
    | build {|ctx|
        pkg install [iptables iproute2]
        hub install [easytier] -c $ctx.cache?

        b conf expose [11010 u11010 22020 11211 8888]

        b with-mount {
            r#'
            #!/usr/bin/env nu
            use libs/tasks.nu

            # ------------------------------------------------------------------
            # Role: server -> run core (admin relay) + easytier-web (config server + UI)
            #       client -> run core only, local file is just a bootstrap that
            #                  points at the web config server (config lives online)
            #
            # EASYTIER_CONFIG  -> path to the core config file (default /data/easytier.toml)
            # EASYTIER_ROLE    -> "server" | "client" (default: client)
            # EASYTIER_CONFIG_SERVER -> client only: udp://<web-host>:22020/<username>
            # ------------------------------------------------------------------

            let role = ($env.EASYTIER_ROLE? | default "client")

            match $role {
                "server" => {
                    # ---- core: central relay, is the admin node (holds network_secret) ----
                    let core_config = ($env.EASYTIER_CONFIG? | default "/data/easytier.toml")
                    if not ($core_config | path exists) {
                        let secret = $env.NETWORK_SECRET?
                        if ($secret | is-empty) {
                            error make { msg: "NETWORK_SECRET is required for a server node" }
                        }
                        let network = $env.NETWORK_NAME? | default "my_mesh_net"
                        let hostname = $env.NODE_NAME? | default "Central-Server"

                        let toml = $'
                            instance_name = "server"
                            hostname = "($hostname)"

                            [network_identity]
                            network_name = "($network)"
                            network_secret = "($secret)"

                            listeners = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010"]
                        '
                        $toml | str trim | lines | each {|l| $l | str trim } | str join "\n" | save $core_config
                        print $"📦 Generated server core config: ($core_config)"
                    }

                    tasks spawn {
                        tag: easytier
                        msg: $"Starting EasyTier core (server): -c ($core_config)"
                        cmd: [
                            /usr/local/bin/easytier-core
                            -c $core_config
                            --rpc-portal "127.0.0.1:15888"
                        ]
                    }

                    # ---- web: config server + management UI ----
                    # Registration is closed by default (whitelist mindset: you add the users
                    # you want; a blocked/revoked user won't silently re-create an account).
                    # Set EASYTIER_WEB_REGISTRATION=true to open self-registration.
                    mut web_cmd = [
                        /usr/local/bin/easytier-web-embed
                        --db /data/et.db
                        --config-server-port 22020
                        --config-server-protocol udp
                        --api-server-port 11211
                        --api-server-addr 127.0.0.1
                        --web-server-port 8888
                        --web-server-addr 127.0.0.1
                        --disable-registration
                    ]
                    if ($env.EASYTIER_WEB_REGISTRATION? | default "false") == "true" {
                        $web_cmd = ($web_cmd | where {|a| $a != "--disable-registration" })
                    }

                    tasks spawn {
                        tag: easytier-web
                        msg: "Starting EasyTier web (config server + UI)"
                        cmd: $web_cmd
                    }
                }

                "client" => {
                    # ---- core client: local file is ONLY bootstrap, config comes online ----
                    let core_config = ($env.EASYTIER_CONFIG? | default "/data/easytier.toml")
                    let hostname = $env.NODE_NAME? | default "Client-Node"

                    if not ($core_config | path exists) {
                        let toml = $'
                            instance_name = "client"
                            hostname = "($hostname)"
                        '
                        $toml | str trim | lines | each {|l| $l | str trim } | str join "\n" | save $core_config
                        print $"📦 Generated client bootstrap config: ($core_config)"
                    }

                    # config-server is a CLI/env field (not in toml) -> route via env
                    let config_server = $env.EASYTIER_CONFIG_SERVER?
                    if ($config_server | is-empty) {
                        error make {
                            msg: "EASYTIER_CONFIG_SERVER is required for client nodes, e.g. udp://SERVER_IP:22020/alice"
                        }
                    }

                    tasks spawn {
                        tag: easytier
                        msg: $"Starting EasyTier core (client) via config-server: ($config_server)"
                        cmd: [
                            /usr/local/bin/easytier-core
                            -c $core_config
                            --config-server $config_server
                            --rpc-portal "127.0.0.1:15888"
                        ]
                    }
                }

                _ => { error make { msg: $"Unknown EASYTIER_ROLE: ($role) (expected server | client)" } }
            }
            '#
            | str trim
            | str replace -rma $'^ {12}' ''
            | save entrypoint/easytier.nu
        }

        # --- config file templates (written into the image, for reference / manual use) ---
        b with-mount {
            mkdir data
            r#'
            # EasyTier server / central relay node -- full reference template.
            # Auto-generated by default when EASYTIER_ROLE=server; mount this in to override.
            instance_name = "server"
            hostname = "Central-Server"

            [network_identity]
            network_name = "my_mesh_net"
            network_secret = "CHANGE_ME"

            listeners = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010"]

            # [flags]
            # mtu = 1380
            '#
            | str trim
            | str replace -rma $'^ {12}' ''
            | save data/server.example.toml

            r#'
            # EasyTier client node -- bootstrap reference template.
            # With EASYTIER_ROLE=client the real config is served online by easytier-web
            # via --config-server (a CLI/env field), so this file only pins hostname + instance.
            instance_name = "client"
            hostname = "Client-Node"

            # Optional advanced options (only used if you drop this file in as the full config):
            # ipv4 = "10.144.144.10"
            # dhcp = true
            # [[peer]]
            # uri = "tcp://10.6.6.1:11010"
            # socks5_proxy = "tcp://0.0.0.0:1080"
            '#
            | str trim
            | str replace -rma $'^ {12}' ''
            | save data/client.example.toml
        }

        b conf workdir /srv
        b conf cmd ['srv']
    }
}