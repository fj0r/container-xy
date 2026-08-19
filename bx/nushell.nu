use b.nu
use trace.nu
use hub.nu
use utils.nu *

export def setup [
    dir
    config: record
    --skip-download
    --cache(-c): string = ''
] {
    trace inc-level

    if not $skip_download {
        trace o -p 'install-nushell' $dir
        hub install [nushell] -t $dir -c $cache -o {|x|
            $x | upsert plugins $config.plugins
        }
    }

    let install_path = $dir | path join bin "nu"
    b exec [
        $"echo '($install_path)' >> /etc/shells"
        $'usermod -s ($install_path) ($config.user)'
    ]

    b with-mount {
        let cfg = open ($env.BX_DATADIR | path join hub.yaml) | get packages.nushell.options.config
        let xdg_config = relative-path $config.xdg_config
        | path expand
        | path join nushell

        mut prev_config = ""
        if ($xdg_config | path exists) {
            $prev_config = open -r ($xdg_config | path join config.nu)
            rm -rf $xdg_config
        }
        git clone --depth=($cfg.clone?.depth? | default 3) $cfg.git $xdg_config

        cd $xdg_config
        git log -1 --date=iso
        $"(char newline)($prev_config)" | save -a config.nu
    }

    let reg = $config.plugins
    | each {|x| $"plugin add ($dir | path join bin nu_plugin_($x))"}
    | str join '; '

    b exec [
        $'chown ($config.user):($config.user) -R ($config.xdg_config)/nushell'
        $'sudo -u ($config.user) ($install_path) -c "($reg)"'
    ]
}
