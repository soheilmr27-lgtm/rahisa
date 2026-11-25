# Rahisa theme development

The installable block theme is in `wp-content/themes/rahisa`. It uses native WordPress templates and keeps WooCommerce's standard product, catalog, cart, and checkout templates available. Shared layout rules use logical CSS properties, so the site's Persian locale controls the reading direction.

## Local preview

With Docker running, run the following from the repository root:

```sh
npx @wordpress/env start
npx @wordpress/env run cli wp language core install fa_IR --activate
npx @wordpress/env run cli wp plugin activate woocommerce
npx @wordpress/env run cli wp theme activate rahisa
```

Open `http://localhost:8888`. Use a separate preview database. Keep production credentials and data out of local fixtures and GitHub. Use Appearance → Editor to review the templates and parts. Export template changes into the theme files before committing them.

## Deployment and rollback

Build and review changes on a feature branch. The server's deployment timer checks `main` and publishes the `wp-content/themes/rahisa` and `wp-content/plugins/rahisa` paths. The preview branch does not change the active production theme.

After an approved merge, inspect the deployment service result and compare the served release to the relevant `main` commit. Theme activation, when approved, is a separate WordPress operation. Record the currently active theme slug before switching.

To roll back a deployment, revert the defective application change on `main` and verify that the timer publishes the previous contents. To roll back theme activation, restore the recorded theme in Appearance → Themes or with `wp theme activate <previous-slug>`. A Git revert does not restore database content.
