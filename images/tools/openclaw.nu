use ../../bx *


export def main [context: record = {}] {
    {
        from: $'($context.image):browser'
        workdir: /app/data
    }
    | merge $context
    | merge { tag: openclaw }
    | upsert skills {|x|
        $x.skills?
        | default []
        | append [
            self-improving #proactive-agent
            ontology
            file-search
            multi-search-engine
            scheduler
            playwright
            github
            ahrefs
        ]
        | uniq
    }
    | upsert plugins {|x|
        $x.plugins?
        | default []
        | append [
        ]
        | uniq
    }
    | build {|ctx|
        b conf env {
            NODE_LLAMA_CPP_SKIP_DOWNLOAD: 'true'
            OPENCLAW_ALLOW_INSECURE_PRIVATE_WS: '1'
            OPENCLAW_HOME: $ctx.workdir
            OPENCLAW_CONFIG_PATH: ($ctx.workdir | path join openclaw.json)
            OPENCLAW_SKILLS: ($ctx.skills | str join ',')
        }

        pkg py install [html2txt]

        let npm_pkgs = [
            node-html-parser
        ]

        pkg js install [
            openclaw
            clawhub
            ...$npm_pkgs
        ]

        let skills_ins = $ctx.skills | each {|x| $'clawhub install ($x)' }

        let plugins_ins = $ctx.plugins | each {|x| $'openclaw plugins install @openclaw/($x)' }

        b exec [
            'mkdir -p /app/data'
            'cd /app'
            # 'npm install --no-cache --omit=optional openclaw'
            ...$plugins_ins
            ...$skills_ins
        ]

        b conf workdir $ctx.workdir
        b copy images/tools/entrypoint/openclaw.nu /entrypoint/openclaw.nu

        b conf expose [18789]
        b conf cmd ['srv']
    }
}
