#!/usr/bin/env -S nu --stdin

const utils = path self utils.nu
use $utils *

const readme = path self README.md

export def main [] {
    let n = $in
    send-file $readme
}
