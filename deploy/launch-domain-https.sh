#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]]
domain=rahisagallery.ir
ip=91.240.95.135
public_url=https://rahisagallery.ir
private_url=http://127.0.0.1:8080
root=/var/www/rahisa/public
wp_config=/var/www/rahisa/wp-config.php
nginx_site=/etc/nginx/sites-available/rahisa-domain.conf
nginx_link=/etc/nginx/sites-enabled/rahisa-domain.conf
cert_dir=/etc/letsencrypt/live/$domain
challenges=/var/lib/letsencrypt/rahisa
backup=$(mktemp -d /root/.rahisa/domain-launch.XXXXXX)
paths_changed=no
urls_changed=no
launched=no

wp_site() {
    runuser -u www-data -- wp --path="$root" --url="$public_url" "$@"
}

restore_if_needed() {
    local result=$?
    trap - EXIT
    set +e
    if [[ $launched == no && $paths_changed == yes ]]; then
        if [[ $urls_changed == yes ]]; then
            wp_site option update home "$old_home"
            wp_site option update siteurl "$old_siteurl"
        fi
        cp -p -- "$backup/wp-config.php" "$wp_config"
        if [[ -f "$backup/nginx.before" ]]; then
            cp -p -- "$backup/nginx.before" "$nginx_site"
        else
            rm -f -- "$nginx_site"
        fi
        if [[ ! -e "$backup/had-link" ]]; then
            rm -f -- "$nginx_link"
        fi
        systemctl reload php8.3-fpm
        nginx -t && systemctl reload nginx
        printf '%s\n' 'Restored the prior site configuration.' >&2
    fi
    exit "$result"
}
trap restore_if_needed EXIT

verify_dns() {
    local host=$1 a aaaa
    a=$(dig @8.8.8.8 "$host" A +time=5 +tries=2 +noall +comments +answer)
    grep -q 'status: NOERROR' <<< "$a" || return 1
    [[ $(awk '$4=="A"{print $5}' <<< "$a" | sort -u) == "$ip" ]] || return 1
    aaaa=$(dig @8.8.8.8 "$host" AAAA +time=5 +tries=2 +noall +comments +answer)
    grep -q 'status: NOERROR' <<< "$aaaa" || return 1
    ! grep -Eq '[[:space:]]AAAA[[:space:]]' <<< "$aaaa"
}

if ! verify_dns "$domain"; then
    printf 'Public DNS must return A %s and no AAAA for %s with this IPv4 configuration.\n' "$ip" "$domain" >&2
    exit 1
fi
hosts=$domain
cert_args=(-d "$domain")
include_www=no
if verify_dns "www.$domain"; then
    hosts="$domain www.$domain"
    cert_args+=(-d "www.$domain")
    include_www=yes
fi

cp -p -- "$wp_config" "$backup/wp-config.php"
if [[ -e "$nginx_link" || -L "$nginx_link" ]]; then
    [[ -L "$nginx_link" && $(readlink "$nginx_link") == "$nginx_site" ]]
    touch "$backup/had-link"
fi
if [[ -f "$nginx_site" ]]; then
    cp -p -- "$nginx_site" "$backup/nginx.before"
fi
old_home=$(wp_site option get home)
old_siteurl=$(wp_site option get siteurl)
db=$(wp_site config get DB_NAME --type=constant)
[[ "$db" =~ ^[a-zA-Z0-9_]+$ ]]
mariadb-dump --single-transaction --skip-lock-tables "$db" | gzip > "$backup/database.sql.gz"
gzip -t "$backup/database.sql.gz"
printf 'Backup: %s\n' "$backup"

python3 - "$wp_config" "$backup/wp-config.after" <<'PY'
from pathlib import Path
import sys

source, target = map(Path, sys.argv[1:])
config = source.read_text()
marker = "// Keep the existing private Rahisa preview available over the SSH tunnel."
anchor = "require_once ABSPATH . 'wp-settings.php';"
if marker not in config:
    if config.count(anchor) != 1:
        raise SystemExit("The WordPress configuration requires review.")
    block = """// Keep the existing private Rahisa preview available over the SSH tunnel.
if (($_SERVER['SERVER_ADDR'] ?? '') === '127.0.0.1' && ($_SERVER['SERVER_PORT'] ?? '') === '8080') {
    define('WP_HOME', 'http://127.0.0.1:8080');
    define('WP_SITEURL', 'http://127.0.0.1:8080');
}

"""
    config = config.replace(anchor, block + anchor)
target.write_text(config)
PY
php -l "$backup/wp-config.after" >/dev/null

install -d -m 0755 "$challenges/.well-known/acme-challenge"
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
    ufw allow 80/tcp
    ufw allow 443/tcp
fi
make_http_config() {
    local default_action=$1
    cat <<NGINX
server {
    listen $ip:80;
    server_name $hosts;
    root $challenges;
    location ^~ /.well-known/acme-challenge/ {
        default_type text/plain;
        try_files \$uri =404;
    }
    location / {
        $default_action
    }
}
NGINX
}

paths_changed=yes
if [[ ! -f "$cert_dir/fullchain.pem" ]]; then
    make_http_config 'return 404;' > "$backup/nginx.acme"
    install -m 0644 "$backup/nginx.acme" "$nginx_site"
    if [[ ! -L "$nginx_link" ]]; then
        ln -s "$nginx_site" "$nginx_link"
    fi
    nginx -t
    systemctl reload nginx
fi
certbot certonly --webroot -w "$challenges" --cert-name "$domain" \
    --non-interactive --agree-tos --register-unsafely-without-email --expand \
    "${cert_args[@]}"

make_http_config 'return 301 https://rahisagallery.ir$request_uri;' > "$backup/nginx.after"
cat >> "$backup/nginx.after" <<'NGINX'
server {
    listen 91.240.95.135:443 ssl;
    server_name rahisagallery.ir;
    ssl_certificate /etc/letsencrypt/live/rahisagallery.ir/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/rahisagallery.ir/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    root /var/www/rahisa/public;
    index index.php;

    location = /wp-config.php { return 404; }
    location ~ /\. { return 404; }
    location ~* ^/wp-content/uploads/.*\.php(?:/|$) { return 403; }
    location / { try_files $uri $uri/ /index.php?$args; }

    location ~ \.php$ {
        try_files $uri =404;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTPS on;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }
}
NGINX
if [[ $include_www == yes ]]; then
    openssl x509 -in "$cert_dir/fullchain.pem" -noout -checkhost "www.$domain"
    cat >> "$backup/nginx.after" <<'NGINX'
server {
    listen 91.240.95.135:443 ssl;
    server_name www.rahisagallery.ir;
    ssl_certificate /etc/letsencrypt/live/rahisagallery.ir/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/rahisagallery.ir/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    return 301 https://rahisagallery.ir$request_uri;
}
NGINX
fi

install -m 0644 "$backup/nginx.after" "$nginx_site"
if [[ ! -L "$nginx_link" ]]; then
    ln -s "$nginx_site" "$nginx_link"
fi
nginx -t
install -o root -g www-data -m 0640 "$backup/wp-config.after" "$wp_config"
urls_changed=yes
wp_site option update home "$public_url"
wp_site option update siteurl "$public_url"
systemctl reload php8.3-fpm
systemctl reload nginx
sleep 3

tls_curl() {
    curl --noproxy '*' -fsSL --max-time 16 --resolve "$domain:443:$ip" "$@"
}
tls_curl "$public_url/" -o "$backup/home.html"
grep -Fqi 'wp-content/' "$backup/home.html"
tls_curl "$public_url/wp-admin/" -o "$backup/admin.html"
grep -Fq 'id="loginform"' "$backup/admin.html"
curl --noproxy '*' -fsSL --max-time 12 "$private_url/wp-admin/" -o "$backup/private-admin.html"
grep -Fq 'id="loginform"' "$backup/private-admin.html"
[[ $(curl --noproxy '*' -sS --max-time 8 --resolve "$domain:80:$ip" -o /dev/null -w '%{redirect_url}' "http://$domain/") == "$public_url/" ]]
wp_site plugin is-active woocommerce
launched=yes

prefix=$(wp_site db prefix)
for stale in "$private_url" http://91.240.95.135; do
    wp_site search-replace "$stale" "$public_url" "${prefix}posts" "${prefix}postmeta" \
        --skip-columns=guid --report-changed-only --dry-run
    if grep -Fq "$stale" "$backup/home.html"; then
        wp_site search-replace "$stale" "$public_url" "${prefix}posts" "${prefix}postmeta" \
            --skip-columns=guid --report-changed-only
    fi
done
tls_curl "$public_url/" -o "$backup/home.html"
if grep -Eq 'http:/{2}(127\.0\.0\.1|localhost|91\.240\.95\.135|rahisagallery\.ir)' "$backup/home.html"; then
    printf '%s\n' 'Review the remaining old-origin or mixed content URLs in the homepage.' >&2
    exit 1
fi

install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/rahisa-nginx <<'HOOK'
#!/bin/sh
set -eu
if [ "$RENEWED_LINEAGE" = /etc/letsencrypt/live/rahisagallery.ir ]; then
    nginx -t
    systemctl reload nginx
fi
HOOK
chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/rahisa-nginx
systemctl enable --now certbot.timer
systemctl is-active certbot.timer
openssl x509 -in "$cert_dir/fullchain.pem" -noout -issuer -enddate -ext subjectAltName
printf 'LAUNCH OK: %s\n' "$public_url"
certbot renew --cert-name "$domain" --dry-run --no-random-sleep-on-renew --non-interactive
