export def exec [acts?: list]: any -> any {
    let n = $in
    $acts
    | default []
    | reduce -f $n {|x, acc|
        let r = $x | split row -r '\s+'
        dispatch $acc $r.0 ($r | slice 1..)
    }
}

def dispatch [input act args?] {
    match $act {
        first => {
            $input | first
        }
        nth => {
            $input | get ($args.0 - 1)
        }
        select => {
            $input | where {|i| $i | parse -r $args.0 | is-not-empty }
        }
        filter => {
            $input | where {|i|
                let f = $i | get $args.0 | into string
                match $args.1 {
                    '==' => { $f == $args.2 }
                    '!=' => { $f != $args.2 }
                }
            }
        }
        from-json => {
            $input | from json
        }
        prefix => {
            $"($args)($input)"
        }
        index => {
            let p = $args | split row '.' | into cell-path
            let r = do -i { $input | get $p }
            if ($r | is-empty) {
                error make { msg: $"'($args)' not in ($input)" }
            } else {
                $r
            }
        }
        trim => {
            $input | str trim
        }
        substr => {
            let s = $args.0? | default '0' | into int
            let e = $args.1? | default '-1' | into int
            $input | str substring $s..$e
        }
        regexp => {
            $input | parse -r $args | get 0?.capture0?
        }
        only-nums => {
            $input | parse -r '(?P<v>[0-9\.\-]+)' | get 0?.v?
        }
        _ => {
            error make {
                msg: $"transformer `($act)` not found"
            }
        }
    }
}
