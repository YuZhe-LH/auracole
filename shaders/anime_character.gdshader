// 角色用卡通着色器，包含柔和分段、边缘光和高光控制。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

// 可从原始材质继承的基础贴图输入。
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;

// 与设置脚本共享的核心颜色参数。
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 shadow_color : source_color = vec4(0.74, 0.8, 0.92, 1.0);
uniform vec4 highlight_color : source_color = vec4(1.0, 0.97, 0.98, 1.0);

// 暴露给检查器的明暗分段、高光与边缘光阈值。
uniform float shadow_threshold : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float shadow_softness : hint_range(0.001, 0.2, 0.001) = 0.035;
uniform float shadow_wrap : hint_range(-0.2, 0.2, 0.01) = 0.04;
uniform float highlight_strength : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float highlight_threshold : hint_range(0.0, 1.0, 0.01) = 0.9;
uniform float highlight_softness : hint_range(0.001, 0.2, 0.001) = 0.03;
uniform float rim_strength : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float rim_threshold : hint_range(0.0, 1.0, 0.01) = 0.72;
uniform float rim_softness : hint_range(0.001, 0.2, 0.001) = 0.08;
uniform float ambient_boost : hint_range(0.0, 1.0, 0.01) = 0.05;
uniform float alpha_cutoff : hint_range(0.0, 1.0, 0.01) = 0.1;


// 采样基础颜色，并为下面的自定义光照函数准备表面数据。
void fragment() {
	vec4 tex = use_texture ? texture(albedo_texture, UV) : vec4(1.0);
	vec4 base = tex * base_color;

	ALBEDO = base.rgb;
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	// Keep character fill light subtle so global glow does not blow out skin and white cloth.
	EMISSION = base.rgb * ambient_boost * 0.08;
}


// 将漫反射、高光和边缘光量化为风格化光照色带。
void light() {
	float ndotl = max(dot(NORMAL, LIGHT) + shadow_wrap, 0.0);
	float light_band = smoothstep(
		shadow_threshold - shadow_softness,
		shadow_threshold + shadow_softness,
		ndotl
	);

	vec3 toon_diffuse = mix(ALBEDO * shadow_color.rgb, ALBEDO, light_band);
	vec3 half_vector = normalize(LIGHT + VIEW);
	float specular_term = max(dot(NORMAL, half_vector), 0.0);
	float specular_band = smoothstep(
		highlight_threshold - highlight_softness,
		highlight_threshold + highlight_softness,
		specular_term
	) * highlight_strength * light_band;

	float view_falloff = 1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	float rim_band = smoothstep(
		rim_threshold - rim_softness,
		rim_threshold + rim_softness,
		view_falloff
	) * rim_strength * light_band;

	DIFFUSE_LIGHT += toon_diffuse * LIGHT_COLOR * ATTENUATION;
	SPECULAR_LIGHT += (highlight_color.rgb * specular_band + highlight_color.rgb * rim_band) * LIGHT_COLOR * ATTENUATION;
}
