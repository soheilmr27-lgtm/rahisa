# Rahisa Gallery

This repository contains the deployment notes and the Nginx template for the initial, Persian-language WordPress and WooCommerce installation. WordPress core, plugins, database contents, private keys, and credentials belong on the VPS and are excluded from the repository.

## 1. Connect the VPS to GitHub

Use the verified SSH host identity for the VPS. On the VPS, create a dedicated Ed25519 SSH key for this repository and keep the private key there. Register the `.pub` file in GitHub under **Settings → Deploy keys** with write access disabled. Verify GitHub's host fingerprint on first use.

```sh
git -c core.sshCommand='ssh -i ~/.ssh/rahisa_github -o IdentitiesOnly=yes' \
  ls-remote --exit-code git@github.com:soheilmr27-lgtm/rahisa.git refs/heads/main
```

If outbound TCP 22 is unavailable, GitHub also offers SSH at `ssh.github.com:443`. Use the SSH URL `ssh://git@ssh.github.com:443/soheilmr27-lgtm/rahisa.git` with the same key. Use SSH for this check so a successful result verifies the deploy key.

## 2. Install the application

1. Confirm the OS, available resources, and which services already own ports 80, 443, and 8080. On Ubuntu 24.04, install the distribution packages `nginx`, `mariadb-server`, `php-fpm`, `php-cli`, `php-mysql`, `php-curl`, `php-gd`, `php-intl`, `php-mbstring`, `php-xml`, `php-zip`, and `curl`. Verify the PHP-FPM socket path before using the template.
2. Create a dedicated local MariaDB database and a user with privileges only on that database. Use a generated password and keep MariaDB off public interfaces. Set up `/var/www/rahisa/public` and use a non-root account to run WP-CLI. Give the PHP worker read access to WordPress and write access where runtime data requires it, such as `wp-content/uploads`.
3. Install a verified stable [WP-CLI release](https://make.wordpress.org/cli/handbook/guides/verifying-downloads/). Download the stable WordPress release with `wp core download --locale=fa_IR`. Create the WordPress configuration for the local database, enter secrets through a secure prompt, and restrict configuration file access. Use `wp core install --url=http://127.0.0.1:8080 --title='Rahisa Gallery' --admin_user=<manager> --admin_email=<manager-email> --skip-email --prompt=admin_password`, substituting the authorized manager details. Verify the locale with `wp option get WPLANG` and set it with `wp language core activate fa_IR` if necessary.
4. Install and activate WooCommerce with `wp plugin install woocommerce --activate`. Enable the [preview Nginx site](deploy/nginx/rahisa-preview.conf) by placing it in `sites-available` and linking it from `sites-enabled` on Ubuntu. Validate with `nginx -t` before reloading. The preview listens on the VPS loopback interface only.

## 3. Verify the preview and enable HTTPS

- From the VPS, check the home and login URLs with `curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/` and the same command against `/wp-login.php`. Inspect any redirects and verify that the login form actually loads before calling the admin available.
- With SSH access, forward a local port to preview the site: `ssh -N -L 127.0.0.1:8080:127.0.0.1:8080 -p <port> <user>@<host>`. Open `http://127.0.0.1:8080/wp-admin/` on that computer. Use an alternate local port only if you also account for the WordPress URL configured for the preview.
- Before publishing, confirm the domain's `A` record matches the VPS's public IPv4 address and that any `AAAA` record routes to this VPS. Limit the certificate to hostnames whose DNS is ready. After the HTTPS virtual host is available, set WordPress `home` and `siteurl` to the final HTTPS URL. If preview URLs were stored in application content, replace them using WP-CLI's serialization-aware `search-replace` after reviewing a dry run. Redirect public HTTP to HTTPS and verify the external home and login URLs.
- Final checks on the VPS: `wp core is-installed`, `wp core verify-checksums`, `wp db check`, `wp plugin is-active woocommerce`, and service health for Nginx, PHP-FPM, and MariaDB. Confirm GitHub access and note the deployed WordPress and WooCommerce versions.

Keep themes, courses, and payment configuration for the next phase.
