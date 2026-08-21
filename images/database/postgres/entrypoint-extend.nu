#!/usr/bin/env nu

def pg-calc-mem [usage: string] {
    let mem = ($usage | split row "," | each { into int })
    let total = ($mem | get 0)
    let work = ($mem | get 1)
    let temp = ($mem | get 2? | default 8)

    let shared = ($total * 0.4 | into int)
    let conn = (($total * 0.6) / ($work + $temp) | into int)

    [
        $"shared_buffers = ($shared)MB"
        $"work_mem = ($work)MB"
        $"temp_buffers = ($temp)MB"
        $"max_connections = ($conn)"
    ]
    | str join "\n"
}

def pg-setup-conf [] {
    let conf_path = $"($env.PGDATA)/usr.conf"
    print $"## Setting up ($conf_path)..."

    # Extract PGCONF_* env vars and convert to PG settings
    # e.g., PGCONF_MAX_CONNECTIONS -> max_connections
    # e.g., PGCONF_LOG__MIN_DURATION -> log.min_duration (using __ as .)
    mut conf_lines = $env
        | transpose key value
        | reduce -f [] {|it, acc|
            let p = $it.key | parse -r "PG(?<t>.+?)_(?<k>.+)"
            if ($p | is-empty) {
                $acc
            } else {
                let p = $p | first
                let k = $p.k | str lowercase | str replace --all "__" "."
                let v = match $p.t {
                    CONF => {
                        $"($k) = ($it.value)"
                    }
                    QONF => {
                        $"($k) = '($it.value)'"
                    }
                }
                $acc | append $v
            }
        }


    # Apply automatic memory calculation if variable exists
    if "POSTGRES_MAX_MEMORY_USAGE" in $env {
        print "  -> Calculating memory usage based on POSTGRES_MAX_MEMORY_USAGE..."
        $conf_lines ++= [pg-calc-mem $env.POSTGRES_MAX_MEMORY_USAGE]
    }

    # Add static instrumentation configs
    $conf_lines ++= [
        "pg_stat_statements.max = 10000"
        "pg_stat_statements.track = all"
    ]

    let seccomp = (
        cat /proc/self/status
        | lines
        | where {|l| ($l | str starts-with 'Seccomp:') }
        | first
        | split row (char tab)
        | get 1
        | str trim
        | into int
    )
    if ($seccomp == 0) {
        $conf_lines ++= ['io_method = io_uring']
    } else {
        print "  -> Launch the container using `--security-opt seccomp=unconfined` to enable io_uring"
        $conf_lines ++= ['io_method = worker']
    }

    # Save to usr.conf (overwriting old settings)
    $conf_lines | str join "\n" | save --force $conf_path
    print "  -> usr.conf updated successfully."
}

def initialize-password [] {
    if ($env.POSTGRES_PASSWORD? | is-empty) {
        let pass = (random chars --length 19)
        $env.POSTGRES_PASSWORD = $pass
        print $"\n[INFO] Random password generated: export $POSTGRES_PASSWORD=($pass)\n"
    }
}

def start-readyset [] {
    if "READYSET_MEMORY_LIMIT" in $env {
        print "## Starting ReadySet service in background..."
        let port = ($env.READYSET_PORT? | default "5433")
        let user = ($env.POSTGRES_USER? | default "postgres")
        let db = ($env.POSTGRES_DB? | default "postgres")
        let pass = $env.POSTGRES_PASSWORD
        let url = $"postgresql://($user):($pass)@localhost:5432/($db)"

        # Run external process in background
        job spawn {
            (
                ^readyset
                --address $"0.0.0.0:($port)"
                --database-type postgresql
                --upstream-db-url $url
                --no-color
                --log-path /var/lib/postgresql/readyset
                --storage-dir /var/lib/postgresql/readyset
                --memory-limit $env.READYSET_MEMORY_LIMIT
            )
        }
    }
}

def main [] {
    initialize-password

    if ($"($env.PGDATA)/postgresql.conf" | path exists) {
        pg-setup-conf
    }

    start-readyset
}
