#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ $EUID -eq 0 ]] || { printf '%s\n' 'Run as root on the Rahisa VPS.' >&2; exit 1; }
repo_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
theme=$repo_dir/wp-content/themes/rahisa
live=/var/www/rahisa/public
stage=$(mktemp -d /var/tmp/rahisa-theme-check.XXXXXX)
work=$stage/public
port=8091
url=http://127.0.0.1:$port
db="rahisa_theme_$(openssl rand -hex 6)"
db_secret=$(openssl rand -hex 24)
server_pid=
db_created=no

cleanup() {
    local result=$?
    trap - EXIT
    set +e
    if [[ -n $server_pid ]]; then
        kill "$server_pid" 2>/dev/null
        wait "$server_pid" 2>/dev/null
    fi
    if [[ $db_created == yes ]]; then
        mariadb -e "DROP DATABASE IF EXISTS $db; DROP USER IF EXISTS '$db'@'localhost';"
    fi
    rm -rf -- "$stage"
    exit "$result"
}
trap cleanup EXIT

[[ -f "$theme/style.css" && -f "$theme/templates/index.html" ]]
find "$theme" -type f -name '*.php' -exec php -l '{}' +
php -r 'json_decode(file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);' "$theme/theme.json"
if ss -ltnH "sport = :$port" | grep -q .; then
    printf 'Preview port %s is already in use.\n' "$port" >&2
    exit 1
fi

chmod 0755 "$stage"
install -d -m 0755 "$work/wp-content/plugins" "$work/wp-content/themes"
for entry in index.php wp-blog-header.php wp-load.php wp-settings.php wp-login.php wp-cron.php wp-admin wp-includes; do
    cp -a -- "$live/$entry" "$work/"
done
cp -a -- "$live/wp-content/languages" "$work/wp-content/"
cp -a -- "$live/wp-content/plugins/woocommerce" "$work/wp-content/plugins/"
cp -a -- "$theme" "$work/wp-content/themes/rahisa"

mariadb -e "CREATE DATABASE $db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
db_created=yes
mariadb <<SQL
CREATE USER '$db'@'localhost' IDENTIFIED BY '$db_secret';
GRANT ALL PRIVILEGES ON $db.* TO '$db'@'localhost';
SQL
cat > "$work/wp-config.php" <<PHP
<?php
define('DB_NAME', '$db');
define('DB_USER', '$db');
define('DB_PASSWORD', '$db_secret');
define('DB_HOST', 'localhost');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');
define('DISABLE_WP_CRON', true);
define('WP_ENVIRONMENT_TYPE', 'staging');
\$table_prefix = 'wp_';
if (!defined('ABSPATH')) { define('ABSPATH', __DIR__ . '/'); }
require_once ABSPATH . 'wp-settings.php';
PHP
unset db_secret
chown -R www-data:www-data "$work"
chmod 0600 "$work/wp-config.php"

wp_stage() {
    runuser -u www-data -- env WP_CLI_CACHE_DIR="$work/wp-content" \
        /usr/local/bin/wp --path="$work" --url="$url" "$@"
}
wp_stage core install --title='Rahisa theme preview' --admin_user=preview-admin \
    --admin_email=preview@example.test --skip-email >/dev/null
wp_stage language core activate fa_IR
wp_stage plugin activate woocommerce
wp_stage theme activate rahisa
wp_stage option update woocommerce_coming_soon no
wp_stage rewrite structure '/%postname%/'
wp_stage eval '
if (!wp_is_block_theme() || get_stylesheet() !== "rahisa" || get_locale() !== "fa_IR" || !is_rtl() || !class_exists("WooCommerce")) {
    exit(1);
}
WC_Install::create_pages();
$product = new WC_Product_Simple();
$product->set_name("Rahisa Preview Product");
$product->set_slug("rahisa-preview-product");
$product->set_regular_price("10000");
$product->set_status("publish");
$product->save();
printf("Block theme, RTL, and WooCommerce loaded. Product ID: %d\n", $product->get_id());
'
shop_url=$(wp_stage eval 'echo wc_get_page_permalink("shop");')
cart_url=$(wp_stage eval 'echo wc_get_cart_url();')
checkout_url=$(wp_stage eval 'echo wc_get_checkout_url();')
product_url=$(wp_stage eval '$p=get_page_by_path("rahisa-preview-product", OBJECT, "product"); echo get_permalink($p);')
product_id=$(wp_stage eval 'echo get_page_by_path("rahisa-preview-product", OBJECT, "product")->ID;')

cat > "$stage/router.php" <<'PHP'
<?php
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
if ($path !== '/' && is_file(__DIR__ . '/public' . $path)) {
    return false;
}
require __DIR__ . '/public/index.php';
PHP
chmod 0644 "$stage/router.php"
timeout 75s runuser -u www-data -- php -S "127.0.0.1:$port" -t "$work" "$stage/router.php" > "$stage/php.log" 2>&1 &
server_pid=$!
curl --noproxy '*' -fsS --retry 3 --retry-connrefused --retry-delay 1 --max-time 12 "$url/" -o "$stage/home.html"
grep -q 'dir="rtl"' "$stage/home.html"
grep -q 'lang="fa-IR"' "$stage/home.html"
grep -q 'themes/rahisa/style.css' "$stage/home.html"
curl --noproxy '*' -fsS --max-time 12 "$url/wp-content/themes/rahisa/style.css" -o "$stage/style.css"
grep -q 'Rahisa' "$stage/style.css"

for page in "$shop_url" "$product_url"; do
    curl --noproxy '*' -fsS --max-time 12 "$page" -o "$stage/product.html"
    grep -q 'Rahisa Preview Product' "$stage/product.html"
done
curl --noproxy '*' -fsSL --max-time 12 -c "$stage/cookies" "$url/?add-to-cart=$product_id" -o /dev/null
curl --noproxy '*' -fsS --max-time 12 -b "$stage/cookies" "$cart_url" -o "$stage/cart.html"
grep -qi 'woocommerce' "$stage/cart.html"
curl --noproxy '*' -fsS --max-time 12 -b "$stage/cookies" "$checkout_url" -o "$stage/checkout.html"
grep -qi 'checkout' "$stage/checkout.html"
printf '%s\n' 'STAGING PASS: Persian RTL, stylesheet, shop, product, cart, checkout.'
