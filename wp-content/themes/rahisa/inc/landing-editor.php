<?php
/** Homepage settings and native WordPress preview controls. */
defined( 'ABSPATH' ) || exit;

function rahisa_home_sections(): array {
	return array(
		'header' => 'سربرگ و منو', 'hero' => 'معرفی اصلی', 'courses' => 'کارت‌های دوره',
		'benefits' => 'ویژگی‌ها', 'academy' => 'معرفی آکادمی', 'gallery' => 'گالری دوخت',
		'faq' => 'پرسش‌های متداول', 'final' => 'دعوت پایانی', 'footer' => 'پاورقی',
		'design' => 'رنگ و شیشه',
	);
}

function rahisa_home_fields(): array {
	static $fields;
	if ( null === $fields ) {
		$fields = wp_json_file_decode( __DIR__ . '/landing-fields.json', array( 'associative' => true ) );
		$sortable = array( 'courses', 'benefits', 'academy', 'gallery', 'faq', 'final' );
		foreach ( $sortable as $index => $key ) {
			$fields[ 'show_' . $key ] = array( 'section' => $key, 'label' => 'نمایش این بخش', 'default' => true, 'type' => 'checkbox' );
			$fields[ 'position_' . $key ] = array( 'section' => $key, 'label' => 'ترتیب نمایش (عدد کوچک‌تر بالاتر)', 'default' => ( $index + 1 ) * 10, 'type' => 'number' );
		}
		$fields['ink'] = array( 'section' => 'design', 'label' => 'رنگ نوشته‌ها', 'default' => '#402219', 'type' => 'color' );
		$fields['accent'] = array( 'section' => 'design', 'label' => 'رنگ دکمه و پیوند فعال', 'default' => '#824b40', 'type' => 'color' );
		$fields['glass'] = array( 'section' => 'design', 'label' => 'شدت لایهٔ شیشه‌ای (۰ تا ۱۰۰)', 'default' => 58, 'type' => 'range' );
	}
	return $fields;
}

function rahisa_home_value( string $key ) {
	$fields = rahisa_home_fields();
	return get_theme_mod( 'rahisa_home_' . $key, $fields[ $key ]['default'] ?? '' );
}

function rahisa_home_link( $value ): string {
	$value = trim( (string) $value );
	if ( '' === $value || preg_match( '/^#[a-zA-Z][a-zA-Z0-9_-]*$/D', $value ) ) {
		return $value;
	}
	return esc_url_raw( $value, array( 'https', 'http', 'mailto', 'tel' ) );
}

function rahisa_home_register_controls( WP_Customize_Manager $manager ): void {
	$manager->add_panel( 'rahisa_home', array( 'title' => 'صفحهٔ اصلی رحیصا', 'priority' => 10 ) );
	foreach ( rahisa_home_sections() as $key => $title ) {
		$manager->add_section( 'rahisa_home_' . $key, array( 'title' => $title, 'panel' => 'rahisa_home' ) );
	}
	$sanitizers = array(
		'link' => 'rahisa_home_link', 'media' => 'absint', 'text' => 'sanitize_text_field',
		'textarea' => 'sanitize_textarea_field', 'lines' => 'sanitize_textarea_field',
		'color' => 'sanitize_hex_color', 'number' => 'absint', 'checkbox' => 'wp_validate_boolean',
		'range' => static function ( $value ) { return min( 100, absint( $value ) ); },
	);
	foreach ( rahisa_home_fields() as $key => $field ) {
		$id = 'rahisa_home_' . $key;
		$type = $field['type'];
		$manager->add_setting( $id, array( 'default' => $field['default'], 'sanitize_callback' => $sanitizers[ $type ] ) );
		$args = array( 'section' => 'rahisa_home_' . $field['section'], 'label' => $field['label'] );
		if ( 'media' === $type ) {
			$args['mime_type'] = 'image';
			$manager->add_control( new WP_Customize_Media_Control( $manager, $id, $args ) );
		} elseif ( 'color' === $type ) {
			$manager->add_control( new WP_Customize_Color_Control( $manager, $id, $args ) );
		} else {
			$args['type'] = array( 'link' => 'text', 'lines' => 'textarea' )[ $type ] ?? $type;
			if ( 'checkbox' === $type || 'number' === $type ) {
				$args['priority'] = 2;
			}
			if ( 'range' === $type ) {
				$args['input_attrs'] = array( 'min' => 0, 'max' => 100 );
			}
			$manager->add_control( $id, $args );
		}
	}
}
add_action( 'customize_register', 'rahisa_home_register_controls' );

add_action( 'admin_menu', static function () {
	add_theme_page( 'صفحهٔ اصلی رحیصا', 'صفحهٔ اصلی رحیصا', 'edit_theme_options', 'customize.php?autofocus[panel]=rahisa_home' );
} );
