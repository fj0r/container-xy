use ../../bx *


export def main [context: record = {}] {
    {
        from: 'python:3.12-slim'
        user: master
        workdir: /home/master
    }
    | merge $context
    | merge { tag: spacy }
    | build {|ctx|
        b conf env {
            PYTHONUNBUFFERED: x
        }

        pkg with [
            rustup
            build-essential
        ] {
            pkg py install [pip setuptools wheel 'spacy[transformers]']
        }
        b exec ['python -m spacy download zh_core_web_trf']
    }
}
