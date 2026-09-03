#!/usr/bin/env -S nu --stdin

const utils = path self utils.nu
use $utils *

# box.nu: 统一数据网关 (读 + 上传 + 列目录) + token 角色鉴权
#   目录分割安全模型 (无目录内部过滤):
#     DATA_ROOT (data/)  - upload 角色读写; '' (无有效 token) 只读
#     HOOKS_ROOT (hooks/) - hook 角色读写 (上传 hook 脚本)
#     META_ROOT  (meta/)   - meta 角色读写 (acl.yml 角色表 + origin.yml 回源清单)
#   URL 形态: box.d/<rel>    rel 相对当前 token 的角色根 (根挂载, 无 box 前缀)
#   鉴权: 请求头 `box-token: <token>` -> META_ROOT/acl.yml 中该 token 的角色
#        role: meta|hook|upload|'' (''=无有效 token, 匿名只读 data)
#   读取无需 token (目录不同而已); 写入要求 role 非空
#   hook 寻址 (核心特性, 保留): 上传到 data/<rel> 时,
#        在 HOOKS_ROOT/<rel> 下解析 run.nu 并执行
#   回源 (box+cache 融合): GET data/<rel> 缺失时, 查 META_ROOT/origin.yml[<rel>]
#        顺序 curl 下载落到 data/<rel> → send-file (等同看待, 与上传混一空间)
#   启动引导: META_ROOT/acl.yml + origin.yml 缺失时首请求生成随机 token / 空 origin
#   安全: 路径穿越防护 (目标必须位于自己的角色根内)
#   数据流: token 只解析一次 (token-role), 根目录存在由启动/部署保证, 不逐请求查

export def main [] {
    # 第一行捕获 stdin (若先调用其他函数会抢占 $in)
    let body = $in
    ensure-bootstrap
    match ($env.REQUEST_METHOD | str lowercase) {
        get         => { serve }
        post | put  => { $body | upload }
        _           => { status 403 }
    }
}

# ── 路径解析 ─────────────────────────────────────────────
# PATH_INFO = /box.nu/box/<rel> (根兜底 rewrite 后): skip 1 去脚本名 box.nu,
#   skip HEAD_LEN(=PREFIX_LEN=1) 去 rewrite 目标中脚本路由段 box, 余下即操作相对路径
def rel-segments [] {
    $env.PATH_INFO
    | path split
    | skip 1
    | skip ($env.PREFIX_LEN? | default 1 | into int)
}
def rel [] { rel-segments | path join }

# 当前 token 的角色: meta|hook|upload|'' (''=无有效 token = 匿名)
# 空串作为 acl.yml 的 record key 合法 (不存在 → get -o 给空 → default '')
def token-role [] {
    open (acl-file) | get -o ($env.HTTP_BOX_TOKEN? | default '') | default ''
}

# role -> 操作根 (纯映射, 无副作用; '' → DATA_ROOT 匿名只读)
def role-root-of [role] {
    match $role {
        meta  => { $env.META_ROOT? | default '' }
        hook   => { $env.HOOKS_ROOT? | default '' }
        _      => { $env.DATA_ROOT? | default '' }   # ''(匿名) 与 upload 都落 data
    }
}

# 逻辑路径不逃逸根 (不解析 symlink, 只规范化 ..)
def inside-root [path root] {
    let p = $path | path expand --no-symlink
    let r = $root | path expand --no-symlink
    $p | str starts-with $r
}

# ── ACL / meta ──────────────────────────────────────────────
def meta-root [] { $env.META_ROOT? | default '' }
def acl-file [] { (meta-root) | path join 'acl.yml' }
def origin-file [] { (meta-root) | path join 'origin.yml' }
def data-root [] { $env.DATA_ROOT? | default '' }
def hooks-root [] { $env.HOOKS_ROOT? | default '' }

def ensure-bootstrap [] {
    let root = meta-root
    mkdir $root
    # acl.yml: token → role 表
    let acl = acl-file
    if not ($acl | path exists) {
        let mt = random chars --length 24
        {
          $mt: meta
          (random chars --length 24): hook
          (random chars --length 24): upload
        }
        | to yaml
        | save -f $acl
        print -e $"(char nl)meta token: ($mt)"
    }
    # origin.yml: rel → 回源 urls 表 (缺失时生成空表)
    let origin = origin-file
    if not ($origin | path exists) {
        {} | to yaml | save -f $origin
    }
}

# ── GET: 读 + 列目录 (无目录内过滤; 无需 token, 仅目录不同) ─
def serve [] {
    let role = token-role
    let root = role-root-of $role
    let path = $root | path join (rel)
    if not (inside-root $path $root) { status 403; return }

    match ($path | path type) {
        file => { send-file $path }
        dir  => { list-dir $path }
        _    => {
            # 回源: 仅 data 空间(匿名/upload)缺失时查 origin.yml 下载落 data
            if $root == (data-root) {
                fetch-from-origin $path
            } else {
                status 404
            }
        }
    }
}

# box+cache 融合: 本地缺失 → 查 meta/origin.yml[rel] → 顺序下载落 data/<rel> → send-file
def fetch-from-origin [path] {
    let key = rel
    let origin = origin-file
    if not ($origin | path exists) { status 404; return }
    # 字符串 key 含斜杠/句号时字面取, 不当嵌套路径解析
    let urls = try { open $origin | get -o $key } catch { null }
    if ($urls | is-empty) { status 404; return }

    let tmp = mktemp
    mut done = false
    for url in $urls {
        let r = curl -fsSL --max-time 600 -o $tmp $url | complete
        let sz = try { ls $tmp | first | get size | into int } catch { 0 }
        if ($r.exit_code == 0 and $sz > 0) {
            mkdir ($path | path dirname)
            mv -f $tmp $path
            $done = true
            break
        }
        rm -f $tmp
    }
    if $done { send-file $path } else { status 404 }
}

def list-dir [dir] {
    content -j
    # 防线前移: cd 进 root 再 ls, name 从源头就是相对路径, 不在输出端事后换算
    cd $dir
    ls
    | select name type size modified
    | to json -r
}

# ── POST/PUT: 上传 (仅有效 token, role 非空) ──────────────
# 命中 hook 时 hook 输出作为响应 (SSE); 否则返回 event JSON
def upload [] {
    let n = $in
    let role = token-role
    if ($role | is-empty) { status 403; return }   # ''=无有效 token, 不可写

    let root = role-root-of $role
    let dest = $root | path join (rel)
    if not (inside-root $dest $root) { status 403; return }

    let parent = $dest | path parse | get parent
    if not ($parent | path exists) { mkdir $parent }
    $n | save -f $dest

    let event = {
        event: "file_uploaded",
        host: $env.HTTP_HOST
        binary: (($n | describe -d).type == 'binary')
        size: (if (($n | describe -d).type == 'binary') { $n | bytes length } else { $n | str length })
        filename: (rel)
        timestamp: (date now | format date "%+")
    }

    # hook 寻址: 仅 upload 传 data 时, 查 HOOKS_ROOT/<rel> 下 run.nu
    let hit = if ($role == 'upload') { run-hook-if-any $event } else { false }
    if not $hit {
        content -j
        $event | upsert location {|e| (rel) } | to json -r
    }
}

# 上传 data 命中 hook 时执行: 在 HOOKS_ROOT/<rel> 下解析 hook 脚本
def run-hook-if-any [event] {
    let segs = rel-segments
    let hooks_root = hooks-root

    mut hook_path = ''
    let paths = [$segs ($segs | drop 1 | append '_')]
        | append (1..($segs | length) | each {|i| $segs | drop $i | append '__'})

    for p in $paths {
        let candidate = $hooks_root | path join ...$p
        if ($candidate | path exists) { $hook_path = $candidate; break }
    }

    if ($hook_path | is-empty) { return false }

    content -s
    let workdir = mktemp -d
    cd $workdir
    let script = [$workdir run.nu] | path join
    $"(open -r $hook_path)\n\nexport def main [] { let o = $in | from json; file_uploaded $o }" | save -f $script
    $event
    | insert location {|e| (rel) }
    | to json -r
    | nu --stdin $script
    cd ..
    rm -rf $workdir
    return true
}