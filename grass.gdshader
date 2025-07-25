// grass.gdshader
// Renders grass blades with wind effects and camera fading.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, unshaded, shadows_disabled;

// --- Fade Uniforms ---
uniform float camera_fade_start : hint_range(10.0, 500.0) = 50.0;
uniform float camera_fade_length : hint_range(1.0, 200.0) = 25.0;

// --- Base Uniforms ---
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color,filter_linear_mipmap,repeat_enable;
uniform float alpha_hash_scale : hint_range(0.0, 2.0, 0.01);

// --- Wind Effect Uniforms ---
group_uniforms wind_effect;
uniform sampler2D wind_noise;
uniform vec2 wind_direction = vec2(1.0, 0.7);
uniform float wind_speed : hint_range(0.0, 5.0) = 0.5;
uniform float wind_strength : hint_range(0.0, 5.0) = 0.2;
uniform float wind_scale : hint_range(0.001, 55.0) = 0.5;

// --- Varyings ---
varying vec3 v_world_pos;

void vertex() {
	vec3 original_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = original_world_pos;

	vec3 instance_world_pos = MODEL_MATRIX[3].xyz;

	vec2 wind_uv = instance_world_pos.xz * wind_scale;
	wind_uv += TIME * wind_speed * normalize(wind_direction);

	float noise_value = texture(wind_noise, wind_uv).r * 2.0 - 1.0;

	float sway_mask = 1.0 - UV.y;
	float offset_amount = noise_value * wind_strength * sway_mask;

	vec3 world_wind_dir = vec3(normalize(wind_direction).x, 0.0, normalize(wind_direction).y);
	vec3 new_world_pos = original_world_pos + (world_wind_dir * offset_amount);

	VERTEX = (inverse(MODEL_MATRIX) * vec4(new_world_pos, 1.0)).xyz;
}

void fragment() {
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = albedo.rgb * albedo_tex.rgb;

	// Calculate the distance from the camera to this pixel.
	float dist = distance(CAMERA_POSITION_WORLD, v_world_pos);
	// Calculate the fade amount using smoothstep for a nice curve.
	float fade_alpha = smoothstep(camera_fade_start + camera_fade_length, camera_fade_start, dist);
	
	// Multiply the final alpha by our fade amount.
	ALPHA = albedo.a * albedo_tex.a * fade_alpha;

	ALPHA_HASH_SCALE = alpha_hash_scale;
}