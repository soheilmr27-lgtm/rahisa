#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $EUID -ne 0 ]]; then
    printf '%s\n' 'Run as root on the Rahisa VPS.' >&2
    exit 1
fi

root=/var/www/rahisa/public
state=/var/lib/rahisa-github-sync
service_user=rahisa-sync
launcher=/usr/local/libexec/rahisa-github-sync
unit=rahisa-github-sync

[[ -f "$root/wp-includes/version.php" ]]
for kind in themes plugins; do
    live_link=$root/wp-content/$kind/rahisa
    target=$state/current/wp-content/$kind/rahisa
    if [[ -e "$live_link" || -L "$live_link" ]]; then
        if [[ ! -L "$live_link" || $(readlink "$live_link") != "$target" ]]; then
            printf 'Existing project files need review: %s\n' "$live_link" >&2
            exit 1
        fi
    fi
done

if ! id "$service_user" >/dev/null 2>&1; then
    useradd --system --user-group --home-dir "$state" --shell /usr/sbin/nologin "$service_user"
fi
install -d -m 0755 /usr/local/libexec
install -d -m 0755 -o "$service_user" -g "$service_user" "$state" "$state/releases"

cat > "$launcher" <<'SYNC'
#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

cd "$STATE_DIRECTORY"
if [[ ! -d repository.git ]]; then
    git init --bare --quiet repository.git
fi

git_repo() {
    git --git-dir=repository.git -c core.hooksPath=/dev/null "$@"
}

git_repo fetch --quiet --no-tags --depth=1 https://github.com/soheilmr27-lgtm/rahisa.git refs/heads/main
revision=$(git_repo rev-parse --verify 'FETCH_HEAD^{commit}')
if [[ $(readlink current || true) == "releases/$revision" ]]; then
    exit 0
fi

release_dir="releases/$revision"
if [[ ! -d "$release_dir" ]]; then
    stage=$(mktemp -d releases/.staging.XXXXXX)
    trap 'rm -rf -- "$stage"' EXIT
    chmod 0755 "$stage"

    for kind in themes plugins; do
        package=wp-content/$kind/rahisa
        if ! git_repo cat-file -e "$revision:$package" 2>/dev/null; then
            continue
        fi
        [[ $(git_repo cat-file -t "$revision:$package") == tree ]]
        git_repo ls-tree -rz "$revision" -- "$package" > "$stage/.entries"
        while IFS= read -r -d '' entry; do
            case "$entry" in
                "100644 "*|"100755 "*) ;;
                *) printf 'Unsupported entry in %s\n' "$package" >&2; exit 1 ;;
            esac
        done < "$stage/.entries"
        rm -- "$stage/.entries"
        git_repo archive --format=tar "$revision" -- "$package" |
            tar --extract --directory="$stage" --no-same-owner --no-same-permissions
        find "$stage/$package" -type f -iname '*.php' -exec php -l '{}' + >/dev/null
    done
    mv -T -- "$stage" "$release_dir"
    trap - EXIT
fi

ln -sfn -- "$release_dir" .next
mv -Tf -- .next current
printf 'GitHub main synchronized at %s\n' "$revision"
SYNC
chmod 0755 "$launcher"

cat > "/etc/systemd/system/$unit.service" <<'SERVICE'
[Unit]
Description=Synchronize Rahisa application assets from GitHub
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=rahisa-sync
Group=rahisa-sync
StateDirectory=rahisa-github-sync
StateDirectoryMode=0755
Environment=GIT_TERMINAL_PROMPT=0
ExecStart=/usr/local/libexec/rahisa-github-sync
TimeoutStartSec=90
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
SERVICE

cat > "/etc/systemd/system/$unit.timer" <<'TIMER'
[Unit]
Description=Check GitHub for Rahisa changes every minute

[Timer]
OnActiveSec=20s
OnUnitInactiveSec=60s
AccuracySec=5s

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl start "$unit.service"

for kind in themes plugins; do
    target=$state/current/wp-content/$kind/rahisa
    live_link=$root/wp-content/$kind/rahisa
    if [[ ! -L "$live_link" ]]; then
        ln -s -- "$target" "$live_link"
    fi
done

systemctl enable --now "$unit.timer"
systemctl is-enabled "$unit.timer"
systemctl is-active "$unit.timer"
readlink "$state/current"
