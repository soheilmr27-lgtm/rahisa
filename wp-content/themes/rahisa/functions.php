<?php
/**
 * Rahisa block theme setup.
 *
 * @package Rahisa
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Make the shared stylesheet available in the editor.
 */
function rahisa_setup(): void {
	add_editor_style( 'style.css' );
}
add_action( 'after_setup_theme', 'rahisa_setup' );

/**
 * Load the theme's layout stylesheet on the front end.
 */
function rahisa_enqueue_styles(): void {
	wp_enqueue_style( 'rahisa', get_stylesheet_uri(), array(), wp_get_theme()->get( 'Version' ) );
}
add_action( 'wp_enqueue_scripts', 'rahisa_enqueue_styles' );
