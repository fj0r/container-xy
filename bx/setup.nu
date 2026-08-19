use b.nu

export def timezone [timezone] {
    b exec [
        $'ln -sf /usr/share/zoneinfo/($timezone) /etc/localtime'
        $'echo "($timezone)" > /etc/timezone'
    ]
}

export def git [author] {
    b exec [
        'git config --global pull.rebase false'
        'git config --global init.defaultBranch main'
        $'git config --global user.name "($author)"'
        $'git config --global user.email "($author)@container"'
    ]
}

export def sudo [] {
    match $env.OS_RELEASE_ID {
        arch => {
            b exec [
                `sed -i 's/# \(%.*NOPASSWD.*\)/&\n\1/' /etc/sudoers`
            ]
        }
        _ => {
            b exec [
                `sed -i 's/^.*\(%sudo.*\)ALL$/\1NOPASSWD: ALL/g' /etc/sudoers`
            ]
        }
    }
}

export def master [
    user: string
    workdir: string
    config_dir: string
] {
    let group = match $env.OS_RELEASE_ID {
        arch => 'wheel'
        debian => 'sudo'
    }
    b exec [
        $'useradd -mU -G ($group),root ($user)'
        $'mkdir -p ($workdir)'
        $'chown ($user):($user) -R ($workdir)'
        $'mkdir -p ($config_dir)'
        $'chown ($user):($user) -R ($config_dir)'
    ]
}
