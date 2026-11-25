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
	$vars = sprintf( '--ink:%s;--accent:%s;--veil:%d%%', sanitize_hex_color( rahisa_home_value( 'ink' ) ) ?: '#402219', sanitize_hex_color( rahisa_home_value( 'accent' ) ) ?: '#824b40', min( 100, absint( rahisa_home_value( 'glass' ) ) ) );
	wp_add_inline_style( 'rahisa-landing', '.rahisa-landing{' . $vars . '}' );
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
 * Select the owner's attachment or the bundled, art-directed image for a slot.
 */
function rahisa_home_image( string $role, string $base ): array {
	$id = absint( rahisa_home_value( 'media_' . $role ) );
	$url = $id ? wp_get_attachment_image_url( $id, 'full' ) : false;
	if ( $url ) {
		$set = wp_get_attachment_image_srcset( $id, 'full' );
		$size = str_contains( $role, 'hero' ) ? '65vw' : '50vw';
		$source = $set ? 'srcset="' . esc_attr( $set ) . '" sizes="' . $size . '"' : 'srcset="' . esc_url( $url ) . '"';
		return array( 'img' => 'src="' . esc_url( $url ) . '" ' . $source, 'source' => $source );
	}
	$vector = in_array( $role, array( 'logo', 'monogram' ), true ) || str_starts_with( $role, 'icon-' );
	$path = $vector ? 'identity/' . $role . '.svg' : 'photos/' . $role . '.webp';
	$src = esc_url( $base . '/' . $path );
	$set = $src;
	if ( ! $vector && is_file( get_theme_file_path( 'assets/landing/photos/' . $role . '@2x.webp' ) ) ) {
		$set .= ' 1x, ' . esc_url( $base . '/photos/' . $role . '@2x.webp' ) . ' 2x';
	}
	return array( 'img' => 'src="' . $src . '" srcset="' . $set . '"', 'source' => 'srcset="' . $set . '"' );
}

/** Order the movable sections, keeping the header, hero and footer in place. */
function rahisa_home_layout( string $template ): string {
	$sections = array();
	$pattern = '~<!-- section ([a-z]+) -->(.*?)<!-- end section -->~s';
	$template = preg_replace_callback( $pattern, static function ( $match ) use ( &$sections ) {
		$key = $match[1];
		if ( 'hero' === $key ) {
			return $match[2] . '{{ordered_sections}}';
		}
		if ( rahisa_home_value( 'show_' . $key ) ) {
			$sections[ $key ] = $match[2];
		}
		return '';
	}, $template );
	uksort( $sections, static function ( $a, $b ) {
		return (int) rahisa_home_value( 'position_' . $a ) <=> (int) rahisa_home_value( 'position_' . $b );
	} );
	return str_replace( '{{ordered_sections}}', implode( "\n", $sections ), $template );
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
	foreach ( $urls as $key => $url ) {
		if ( 'assets' !== $key ) {
			$urls[ $key ] = rahisa_home_value( 'url_' . $key ) ?: $url;
		}
	}
	$urls           = apply_filters( 'rahisa_landing_urls', $urls );
	$replacements   = array();

	foreach ( array( 'side-seam', 'princess', 'trousers' ) as $course ) {
		$replacements[ '{{' . $course . '-note}}' ] = empty( $urls[ $course ] )
			? '<span class="rahisa-sr">؛ وضعیت ثبت‌نام</span>'
			: '';
		$urls[ $course ] = $urls[ $course ] ?: ( rahisa_home_value( 'show_faq' ) ? '#enrollment' : $account );
	}

	$legal = '';
	foreach ( array( 'privacy' => 'حریم خصوصی', 'terms' => 'شرایط استفاده' ) as $key => $label ) {
		$url = esc_url( $urls[ $key ] ?? '' );
		if ( $url ) {
			$legal .= '<a href="' . $url . '">' . esc_html( rahisa_home_value( 'label_' . $key ) ) . '</a>';
		}
	}

	foreach ( $urls as $key => $url ) {
		$replacements[ '{{' . $key . '}}' ] = esc_url( $url );
	}
	$replacements['{{legal}}'] = $legal;

	$social = '';
	foreach ( array( 'instagram' => 'اینستاگرام', 'telegram' => 'تلگرام', 'youtube' => 'یوتیوب' ) as $key => $label ) {
		$link = rahisa_home_value( 'url_' . $key );
		if ( $link ) {
			$social .= '<a href="' . esc_url( $link ) . '">' . esc_html( rahisa_home_value( 'label_' . $key ) ) . '</a>';
		}
	}
	$replacements['{{social}}'] = $social;
	foreach ( rahisa_home_fields() as $key => $field ) {
		$value = rahisa_home_value( $key );
		if ( 'media' === $field['type'] ) {
			$role = substr( $key, 6 );
			foreach ( rahisa_home_image( $role, $urls['assets'] ) as $type => $attributes ) {
				$replacements[ '{{' . $type . '_' . $role . '}}' ] = $attributes;
			}
		} elseif ( 'link' === $field['type'] ) {
			$replacements[ '{{' . $key . '}}' ] = esc_url( $value );
		} else {
			$text = esc_html( (string) $value );
			$replacements[ '{{' . $key . '}}' ] = 'lines' === $field['type'] ? nl2br( $text, false ) : $text;
		}
	}
	$template = rahisa_home_layout( (string) file_get_contents( __DIR__ . '/landing.html' ) );
	$html = strtr( $template, $replacements );
	foreach ( array( 'courses', 'academy', 'gallery', 'faq' ) as $section ) {
		if ( ! rahisa_home_value( 'show_' . $section ) ) {
			$target = 'courses' === $section && function_exists( 'wc_get_page_permalink' ) ? wc_get_page_permalink( 'shop' ) : '#rahisa-main';
			$html = str_replace( 'href="#' . $section . '"', 'href="' . esc_url( $target ?: '#rahisa-main' ) . '"', $html );
		}
	}
	return $html;
}
/**
 * Render the landing as a native block so its markup keeps its own structure.
 */
function rahisa_register_landing_block(): void {
	register_block_type(
		'rahisa/landing',
		array(
			'api_version'     => 3,
			'render_callback' => 'rahisa_render_landing',
		)
	);
}
add_action( 'init', 'rahisa_register_landing_block' );


// Keep the homepage title and description in the same editorial workflow.
add_filter( 'pre_get_document_title', static function ( $title ) {
	return is_front_page() ? rahisa_home_value( 'meta_title' ) : $title;
} );
add_action( 'wp_head', static function () {
	if ( is_front_page() && rahisa_home_value( 'meta_desc' ) ) {
		printf( '<meta name="description" content="%s">' . "\n", esc_attr( rahisa_home_value( 'meta_desc' ) ) );
	}
} );
