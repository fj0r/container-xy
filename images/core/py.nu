use ../../bx *

def derive [context src layer] {
    {
        from: $'($context.image):($src)'
        user: master
        workdir: /home/master
    }
    | merge $context
    | merge { tag: $layer.tag }
    | build {|ctx|
        pkg py install --stack $layer.stack $layer.pkgs
    }
}

export def main [context: record = {}] {
    {
        from: $'($context.image):deb'
        user: master
        workdir: /home/master
    }
    | merge $context
    | merge { tag: py }
    | build {|ctx|
        pkg setup py --stack [web dev io cli utils logging db codec]
    }


    {
        from: $'($context.image):py'
        user: master
        workdir: /home/master
    }
    | merge $context
    | merge { tag: py-data }
    | build {|ctx|
        pkg with [git gcc python3-dev] {
            pkg py install [polars deltalake pyiceberg[rest-sigv4,pyarrow] zstandard]
        }
    }


    {
        from: $'($context.image):py-data'
        user: master
        workdir: /home/master
    }
    | merge $context
    | merge { tag: py-duckdb }
    | build {|ctx|
        pkg setup py [duckdb]

        [
            httpfs
            vortex
            delta
            ducklake
            iceberg
            lance
            postgres
            mysql
            sqlite
            fts
        ]
        | each {|x|
            $"python3 -c \"import duckdb; duckdb.execute\('INSTALL ($x);'\)\""
        }
        | b run $in
    }
}
