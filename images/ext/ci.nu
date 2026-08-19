use ../../bx *

export def main [context: record = {}] {
    {
        from: $'($context.image):latest'
        user: master
        workdir: /home/master
        tag: ci
    }
    | merge $context
    | build {|ctx|
        pkg install [
            buildah skopeo podman
            jq fd ripgrep
        ]
        hub install [kubectl helm]

        pkg py install [
            furl markdown
            ansible kubernetes
            kafka-python
            pymongo github3.py
        ]
        [
            ansible.posix
            community.docker
            community.mongodb
            community.mysql
            community.postgresql
            community.general
            community.windows
            kubernetes.core
        ]
        | each { $"ansible-galaxy collection install ($in)" }
        | b exec $in

        b with-mount {|new, old|
            let tg = $new | path join root/.config/nushell/scripts
            mkdir $tg
            for f in [bx hub.yaml] {
                cp -r ($old | path join $f) $tg
            }
        }
    }
}
