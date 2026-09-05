def uploaded [o] {
    $o | to yaml | print $in
    for i in 1..3 {
        sleep 1sec
        print $i
    }
}
