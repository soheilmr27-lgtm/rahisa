#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if [[ $EUID -ne 0 ]]; then
    printf '%s\n' 'Run this script as root.' >&2
    exit 1
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
state_dir=/root/.rahisa
site_dir=/var/www/rahisa
site_root=$site_dir/public
preview_url=http://127.0.0.1:8080
site_config=$site_dir/wp-config.php
nginx_site=/etc/nginx/sites-available/rahisa-preview.conf
wp_cli=/usr/local/bin/wp
admin_email=$(printenv RAHISA_ADMIN_EMAIL || printf '%s' admin@rahisagallery.ir)

install -d -m 0700 "$state_dir"
install -d -m 0755 "$site_dir"
install -d -o www-data -g www-data -m 0755 "$site_root"
install -d -o www-data -g www-data -m 0700 /var/cache/rahisa-wp-cli

if [[ -e "$site_root/wp-config.php" || ( -e "$site_config" && ! -e "$state_dir/database-password" ) ]]; then
    printf '%s\n' 'An existing WordPress configuration requires inspection.' >&2
    exit 1
fi

if [[ ! -x "$wp_cli" ]]; then
    wp_download=$(mktemp -d)
    trap 'rm -rf -- "$wp_download"' EXIT
    curl --fail --silent --show-error --location --retry 2 --connect-timeout 12 --max-time 75 \
        --proto '=https' --proto-redir '=https' --output "$wp_download/wp-cli.phar" \
        https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        --output "$wp_download/wp-cli.phar.sha512" \
        https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar.sha512
    checksum=$(awk 'NR == 1 {print $1}' "$wp_download/wp-cli.phar.sha512")
    [[ "$checksum" =~ ^[[:xdigit:]]{128}$ ]]
    (cd "$wp_download" && printf '%s  wp-cli.phar\n' "$checksum" | sha512sum --check --status)
    install -m 0755 "$wp_download/wp-cli.phar" "$wp_cli"
fi

wp_site() {
    runuser -u www-data -- env WP_CLI_CACHE_DIR=/var/cache/rahisa-wp-cli "$wp_cli" --path="$site_root" "$@"
}

systemctl enable --now mariadb php8.3-fpm nginx

if [[ ! -f "$site_root/wp-includes/version.php" ]]; then
    wp_site core download --locale=fa_IR
fi
wp_site core verify-checksums --locale=fa_IR

if [[ ! -f "$state_dir/database-password" ]]; then
    openssl rand -hex 32 > "$state_dir/database-password"
fi
db_password=$(<"$state_dir/database-password")
[[ "$db_password" =~ ^[[:xdigit:]]{64}$ ]]
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS rahisa_wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'rahisa_wp'@'localhost' IDENTIFIED BY '$db_password';
GRANT ALL PRIVILEGES ON rahisa_wordpress.* TO 'rahisa_wp'@'localhost';
SQL

if [[ ! -f "$site_config" ]]; then
    config_temp=$(mktemp "$state_dir/wordpress-config.XXXXXX")
    {
        printf '%s\n' '<?php'
        printf "define('DB_NAME', 'rahisa_wordpress');\n"
        printf "define('DB_USER', 'rahisa_wp');\n"
        printf "define('DB_PASSWORD', '%s');\n" "$db_password"
        printf "define('DB_HOST', 'localhost');\n"
        printf "define('DB_CHARSET', 'utf8mb4');\n"
        printf "define('DB_COLLATE', '');\n"
        for constant in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
            printf "define('%s', '%s');\n" "$constant" "$(openssl rand -hex 48)"
        done
        printf '%s\n' "\$table_prefix = 'wp_';"
        printf '%s\n' "define('DISALLOW_FILE_EDIT', true);"
        printf '%s\n' "define('WP_DEBUG', false);"
        printf '%s\n' "if (!defined('ABSPATH')) { define('ABSPATH', __DIR__ . '/public/'); }"
        printf '%s\n' "require_once ABSPATH . 'wp-settings.php';"
    } > "$config_temp"
    php -l "$config_temp" >/dev/null
    install -o root -g www-data -m 0640 "$config_temp" "$site_config"
    rm -- "$config_temp"
fi
unset db_password

if ! wp_site core is-installed; then
    if [[ ! -f "$state_dir/wordpress-admin-password" ]]; then
        openssl rand -hex 24 > "$state_dir/wordpress-admin-password"
    fi
    wp_site core install --url="$preview_url" --title='رحیصا گالری' \
        --admin_user=rahisa-owner --admin_email="$admin_email" --locale=fa_IR \
        --skip-email --prompt=admin_password < "$state_dir/wordpress-admin-password"
fi

if ! wp_site plugin is-active woocommerce; then
    if wp_site plugin is-installed woocommerce; then
        wp_site plugin activate woocommerce
    else
        wp_site plugin install woocommerce --activate
    fi
fi

install -m 0644 "$script_dir/nginx/rahisa-preview.conf" "$nginx_site"
ln -sfn "$nginx_site" /etc/nginx/sites-enabled/rahisa-preview.conf
nginx -t
if [[ $(readlink /etc/nginx/sites-enabled/default || true) = /etc/nginx/sites-available/default ]]; then
    unlink /etc/nginx/sites-enabled/default
fi
nginx -t
systemctl reload nginx

wp_site db check
wp_site plugin is-active woocommerce
[[ $(wp_site option get WPLANG) = fa_IR ]]
printf 'WordPress %s, WooCommerce %s\n' "$(wp_site core version)" "$(wp_site plugin get woocommerce --field=version)"
curl --fail --silent --show-error --max-time 15 --output /dev/null --write-out 'Homepage: %{http_code}\n' "$preview_url/"
curl --fail --silent --show-error --max-time 15 --location --output /dev/null --write-out 'Admin login: %{http_code}\n' "$preview_url/wp-admin/"

install -d -m 0700 /root/.ssh
if [[ ! -f /root/.ssh/rahisa_github ]]; then
    ssh-keygen -q -t ed25519 -C rahisa-vps-deploy -N '' -f /root/.ssh/rahisa_github
fi
printf '%s\n' 'Preview verified. Deploy key public file: /root/.ssh/rahisa_github.pub'
