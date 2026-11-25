<?php
/**
 * Home template integration.
 *
 * @package Rahisa
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Load homepage-only assets.
 */
function rahisa_landing_enqueue(): void {
	if ( ! is_front_page() ) {
		return;
	}

	$directory = get_theme_file_path( 'assets/landing' );
	$uri       = get_theme_file_uri( 'assets/landing' );
	wp_enqueue_style( 'rahisa-landing', $uri . '/landing.css', array( 'rahisa' ), (string) filemtime( $directory . '/landing.css' ) );
	wp_enqueue_script( 'rahisa-landing', $uri . '/landing.js', array(), (string) filemtime( $directory . '/landing.js' ), array( 'strategy' => 'defer', 'in_footer' => true ) );
}
add_action( 'wp_enqueue_scripts', 'rahisa_landing_enqueue' );

/**
 * Resolve a course by its saved product slug or exact Persian title.
 */
function rahisa_landing_course_url( string $slug, string $title ): string {
	if ( ! function_exists( 'wc_get_product' ) ) {
		return '';
	}

	$product = get_page_by_path( $slug, OBJECT, 'product' );
	if ( ! $product || 'publish' !== $product->post_status ) {
		$query   = new WP_Query(
			array(
				'post_type'              => 'product',
				'post_status'            => 'publish',
				'title'                  => $title,
				'posts_per_page'         => 1,
				'no_found_rows'          => true,
				'update_post_meta_cache' => false,
				'update_post_term_cache' => false,
			)
		);
		$product = $query->posts[0] ?? null;
	}

	return $product && 'publish' === $product->post_status ? get_permalink( $product ) : '';
}

/**
 * Render the same landing markup with real URLs from the WordPress installation.
 */
function rahisa_render_landing(): string {
	if ( ! is_front_page() ) {
		return '';
	}

	$account = function_exists( 'wc_get_page_id' ) && wc_get_page_id( 'myaccount' ) > 0
		? wc_get_page_permalink( 'myaccount' )
		: wp_login_url( home_url( '/' ) );

	$urls = array(
		'assets'    => get_theme_file_uri( 'assets/landing' ),
		'home'      => home_url( '/' ),
		'account'   => $account,
		'side-seam' => rahisa_landing_course_url( 'side-seamless-blazer', 'کت بدون درز پهلو' ),
		'princess'  => rahisa_landing_course_url( 'princess-seam-blazer', 'کت با برش عصایی' ),
		'trousers'  => rahisa_landing_course_url( 'tailored-trousers', 'شلوار' ),
		'privacy'   => get_privacy_policy_url(),
	);

	$terms_id       = function_exists( 'wc_get_page_id' ) ? wc_get_page_id( 'terms' ) : 0;
	$urls['terms']  = $terms_id > 0 && 'publish' === get_post_status( $terms_id ) ? get_permalink( $terms_id ) : '';
	$urls           = apply_filters( 'rahisa_landing_urls', $urls );
	$replacements   = array();

	foreach ( array( 'side-seam', 'princess', 'trousers' ) as $course ) {
		$replacements[ '{{' . $course . '-note}}' ] = empty( $urls[ $course ] )
			? '<span class="rahisa-sr">؛ وضعیت ثبت‌نام</span>'
			: '';
		$urls[ $course ] = $urls[ $course ] ?: '#enrollment';
	}

	$legal = '';
	foreach ( array( 'privacy' => 'حریم خصوصی', 'terms' => 'شرایط استفاده' ) as $key => $label ) {
		$url = esc_url( $urls[ $key ] ?? '' );
		if ( $url ) {
			$legal .= '<a href="' . $url . '">' . esc_html( $label ) . '</a>';
		}
	}

	foreach ( $urls as $key => $url ) {
		$replacements[ '{{' . $key . '}}' ] = esc_url( $url );
	}
	$replacements['{{legal}}'] = $legal;

	return strtr( (string) file_get_contents( __DIR__ . '/landing.html' ), $replacements );
}
add_shortcode( 'rahisa_landing', 'rahisa_render_landing' );
