use ../../bx *

export def main [context: record = {}] {
    $context
    | update image {|x|
        $x.image | path split | slice ..-2 | append 'assets' | path join
    }
    | merge {
        from: 'scratch'
        tag: qwen3-4b
        model: 'Qwen/Qwen3-4B-Instruct-2507'
    }
    | build {|ctx|
        let r = $ctx
        | merge { from: $'($context.image):mistralrs' }
        | build --no-commit {|ctx|
            b exec [
                $"'\\exit' | mistralrs run -m ($ctx.model)"
            ]
        }

        b with-mount {|new, old|
            cd ($r.BUILDAH_WORKING_MOUNTPOINT | path join root/.cache)
            mv huggingface $new
        }

        buildah unmount $r.BUILDAH_WORKING_CONTAINER
    }
}
