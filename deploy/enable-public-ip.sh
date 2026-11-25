#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

public_url=http://91.240.95.135
private_url=http://127.0.0.1:8080
repo=soheilmr27-lgtm/rahisa
checkout=/opt/rahisa
root=/var/www/rahisa/public
wp_config=/var/www/rahisa/wp-config.php
nginx_site=/etc/nginx/sites-available/rahisa-public-ip.conf
nginx_link=/etc/nginx/sites-enabled/rahisa-public-ip.conf
sync_dir=/var/lib/rahisa-github-sync
key=/root/.ssh/rahisa_github
transaction=$(mktemp -d /root/rahisa-public-ip.XXXXXX)
changed=no
completed=no

cleanup() {
    local exit_status=$?
    trap - EXIT
    set +e
    if [[ $changed == yes && $completed == no ]]; then
        cp -p -- "$transaction/wp-config.before" "$wp_config"
        if [[ -f "$transaction/nginx.before" ]]; then
            cp -p -- "$transaction/nginx.before" "$nginx_site"
        else
            rm -f -- "$nginx_site"
        fi
        if [[ ! -e "$transaction/had-link" ]]; then
            rm -f -- "$nginx_link"
        fi
        systemctl reload php8.3-fpm
        nginx -t && systemctl reload nginx
        printf '%s\n' 'Rolled back the public IP configuration.' >&2
    fi
    rm -rf -- "$transaction"
    exit "$exit_status"
}
trap cleanup EXIT

check_github_key() {
    local route endpoint host port target common greeting read_result write_result
    [[ -f "$key" && -f "$key.pub" ]] || { printf '%s\n' 'GitHub deploy key is absent.'; return 1; }
    ssh-keygen -lf "$key.pub"
    local github_host_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl'
    printf '%s %s\n' github.com "$github_host_key" '[ssh.github.com]:443' "$github_host_key" > "$transaction/github-known-hosts"
    common="ssh -F /dev/null -i $key -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes -o HostKeyAlgorithms=ssh-ed25519 -o UserKnownHostsFile=$transaction/github-known-hosts"
    for route in standard alternate; do
        if [[ $route == standard ]]; then
            host=github.com
            port=22
            endpoint="git@github.com:$repo.git"
        else
            host=ssh.github.com
            port=443
            endpoint="ssh://git@ssh.github.com:443/$repo.git"
        fi
        printf 'Testing deploy key via %s:%s\n' "$host" "$port"
        greeting=$($common -T -p "$port" "git@$host" 2>&1) || true
        printf '%s\n' "$greeting"
        if [[ "$greeting" != *"Hi $repo!"* ]]; then
            continue
        fi
        read_result=$(GIT_SSH_COMMAND="$common" git -C "$checkout" ls-remote --exit-code "$endpoint" refs/heads/main 2>&1) || {
            printf '%s\n' "$read_result"; return 1;
        }
        printf 'SSH_READ %s\n' "$read_result"
        printf '%s\n' "$read_result" | awk '{print $1}' > "$transaction/github-main"
        target="refs/heads/rahisa-deploy-key-check-$(date +%s)"
        write_result=$(GIT_SSH_COMMAND="$common" git -C "$checkout" push --dry-run --porcelain "$endpoint" "HEAD:$target" 2>&1) || {
            printf '%s\n' "$write_result"; return 1;
        }
        printf 'SSH_WRITE_DRY_RUN %s\n' "$write_result"
        return 0
    done
    return 1
}
check_github_key || printf '%s\n' 'GitHub deploy key verification incomplete; inspect the SSH messages above.'

systemctl start rahisa-github-sync.service
systemctl is-active rahisa-github-sync.timer
systemctl show rahisa-github-sync.service -p Result -p ExecMainStatus
synced=$(git --git-dir="$sync_dir/repository.git" rev-parse FETCH_HEAD)
printf 'SYNC_COMMIT %s\n' "$synced"
[[ $(readlink "$sync_dir/current") == "releases/$synced" ]]
if [[ -s "$transaction/github-main" ]]; then
    [[ $(<"$transaction/github-main") == "$synced" ]]
fi
printf 'Project source paths: %s\n' wp-content/themes/rahisa wp-content/plugins/rahisa
git --git-dir="$sync_dir/repository.git" ls-tree "$synced" -- wp-content/themes/rahisa wp-content/plugins/rahisa

wp_site() {
    runuser -u www-data -- wp --path="$root" --url="$private_url" "$@"
}
wp_site core is-installed
wp_site plugin is-active woocommerce
printf 'WORDPRESS %s WOOCOMMERCE %s\n' "$(wp_site core version)" "$(wp_site plugin get woocommerce --field=version)"
printf 'PRIVATE_HOME %s PRIVATE_SITEURL %s\n' "$(wp_site option get home)" "$(wp_site option get siteurl)"
curl -fsSL --noproxy '*' --max-time 12 "$private_url/wp-admin/" -o "$transaction/private-before.html"
grep -Fq 'id="loginform"' "$transaction/private-before.html"

if [[ -e "$nginx_link" || -L "$nginx_link" ]]; then
    [[ -L "$nginx_link" && $(readlink "$nginx_link") == "$nginx_site" ]]
    touch "$transaction/had-link"
fi
if [[ -f "$nginx_site" ]]; then
    cp -p -- "$nginx_site" "$transaction/nginx.before"
fi
cp -p -- "$wp_config" "$transaction/wp-config.before"

python3 - "$wp_config" "$transaction/wp-config.after" <<'PY'
from pathlib import Path
import sys

source, output = map(Path, sys.argv[1:])
config = source.read_text()
tag = "// Rahisa public IP preview."
anchor = "require_once ABSPATH . 'wp-settings.php';"
if tag not in config:
    if config.count(anchor) != 1 or "WP_HOME" in config or "WP_SITEURL" in config:
        raise SystemExit("Existing WordPress URL configuration requires review.")
    block = """// Rahisa public IP preview.
if (($_SERVER['RAHISA_PUBLIC_ORIGIN'] ?? '') === 'http://91.240.95.135') {
    define('WP_HOME', 'http://91.240.95.135');
    define('WP_SITEURL', 'http://91.240.95.135');
}

"""
    config = config.replace(anchor, block + anchor)
output.write_text(config)
PY
php -l "$transaction/wp-config.after" >/dev/null

cat > "$transaction/nginx.after" <<'NGINX'
server {
    listen 91.240.95.135:80 default_server;
    server_name 91.240.95.135;
    root /var/www/rahisa/public;
    index index.php;

    if ($host != 91.240.95.135) { return 421; }
    if ($request_method !~ ^(GET|HEAD)$) { return 405; }

    location = /wp-admin { return 403; }
    location ^~ /wp-admin/ { return 403; }
    location = /wp-login.php { return 403; }
    location ~ /\. { return 404; }

    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location = /index.php {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root/index.php;
        fastcgi_param HTTP_HOST 91.240.95.135;
        fastcgi_param RAHISA_PUBLIC_ORIGIN http://91.240.95.135;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    location ~* \.php(?:/|$) { return 404; }
}
NGINX

changed=yes
install -m 0644 "$transaction/nginx.after" "$nginx_site"
if [[ ! -L "$nginx_link" ]]; then
    ln -s -- "$nginx_site" "$nginx_link"
fi
nginx -t
install -o root -g www-data -m 0640 "$transaction/wp-config.after" "$wp_config"
systemctl reload php8.3-fpm
systemctl reload nginx
sleep 3

curl --noproxy '*' -fsS --max-time 15 -D "$transaction/public-headers" "$public_url/" -o "$transaction/public.html"
head -n 1 "$transaction/public-headers"
grep -i '^location:' "$transaction/public-headers" || true
grep -Eq '^HTTP/[0-9.]+ 200 ' "$transaction/public-headers"
grep -Fqi 'wp-content/' "$transaction/public.html"
if grep -Eqi '127\.0\.0\.1|localhost:8080' "$transaction/public.html"; then
    printf '%s\n' 'The public homepage contains a private URL.' >&2
    exit 1
fi
test "$(curl --noproxy '*' -sS --max-time 10 -o /dev/null -w '%{http_code}' "$public_url/wp-admin/")" = 403
curl --noproxy '*' -fsSL --max-time 12 "$private_url/wp-admin/" -o "$transaction/private-after.html"
grep -Fq 'id="loginform"' "$transaction/private-after.html"

python3 - "$transaction/public.html" <<'PY'
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urljoin, urlsplit
from urllib.request import ProxyHandler, build_opener, Request
import sys

base = "http://91.240.95.135/"

class Assets(HTMLParser):
    paths = {}
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "link" and "stylesheet" in attrs.get("rel", "").split():
            self.add("CSS", attrs.get("href"))
        if tag == "script":
            self.add("JS", attrs.get("src"))
        if tag == "img":
            self.add("image", attrs.get("src"))

    def add(self, kind, path):
        if path:
            url = urljoin(base, path)
            if urlsplit(url).netloc == urlsplit(base).netloc:
                self.paths[url] = kind

assets = Assets()
assets.feed(Path(sys.argv[1]).read_text())
opener = build_opener(ProxyHandler({}))
counts = Counter()
for url, kind in assets.paths.items():
    with opener.open(Request(url, method="HEAD"), timeout=12) as response:
        if response.status != 200 or urlsplit(response.url).netloc != urlsplit(base).netloc:
            raise SystemExit("Asset failed validation: " + url)
        counts[kind] += 1
print("PUBLIC_ASSETS", dict(counts))
PY
completed=yes
printf 'PUBLIC_OK %s PRIVATE_ADMIN_OK %s/wp-admin/\n' "$public_url/" "$private_url"
