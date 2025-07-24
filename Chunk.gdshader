// Chunk.gdshader
// Renders the terrain by blending multiple textures based on world height, slope, and path data.
// Path rendering is constrained by slope and height rules.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// --- Textures ---
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D texture_albedo_snow : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_albedo_grass : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_albedo_sand : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_albedo_slope : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D texture_albedo_path : source_color, filter_linear_mipmap, repeat_enable;

// --- Height Blending ---
uniform float snow_start_height : hint_range(0.0, 200.0) = 80.0;
uniform float snow_full_height : hint_range(0.0, 200.0) = 100.0;
uniform float sand_start_height : hint_range(-200.0, 50.0) = -5.0;
uniform float sand_full_height : hint_range(-200.0, 50.0) = -25.0;

// --- Slope Blending ---
uniform float slope_threshold : hint_range(-1.0, 1.0) = 0.7;
uniform float slope_blend_range : hint_range(0.0, 1.0) = 0.2;

// --- Path Height Constraint ---
uniform float path_fade_start_y : hint_range(0.0, 50.0) = 8.0;
uniform float path_fade_end_y : hint_range(0.0, 50.0) = 10.0;

// --- Standard PBR ---
uniform float specular : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float metallic : hint_range(0.0, 1.0, 0.01) = 0.0;

// --- UV Control ---
uniform float world_uv_scale : hint_range(0.01, 10.0) = 0.1;

// --- Varyings ---
// Data passed from the vertex to the fragment shader.
varying float v_world_normal_y;
varying vec3 v_world_pos;
varying float v_path_influence; // The base strength of the path at this fragment.

void vertex() {
	// Calculate world-space position.
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Calculate world-space normal's Y component.
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_normal_y = world_normal.y;

	// Pass the base path influence (from the red vertex color channel) to the fragment shader.
	v_path_influence = COLOR.r;
}

// Helper function to sample textures using world coordinates for seamless tiling.
vec4 sample_world(sampler2D tex, vec3 world_pos, float scale) {
	// Use the XZ plane for UVs and apply tiling scale.
	vec2 world_uv = world_pos.xz * scale;
	return texture(tex, world_uv);
}

void fragment() {
	// Get interpolated values from the vertex shader.
	vec3 world_pos = v_world_pos;
	float world_normal_y = v_world_normal_y;

	// 1. Height-Based Material Determination.
	vec3 albedo_snow = sample_world(texture_albedo_snow, world_pos, world_uv_scale).rgb;
	vec3 albedo_grass = sample_world(texture_albedo_grass, world_pos, world_uv_scale).rgb;
	vec3 albedo_sand = sample_world(texture_albedo_sand, world_pos, world_uv_scale).rgb;

	float snow_mix = smoothstep(snow_start_height, snow_full_height, world_pos.y);
	// For sand, the blend increases as height decreases, so start/full are swapped.
	float sand_mix = smoothstep(sand_start_height, sand_full_height, world_pos.y);

	// Blend Albedo: Start with grass, blend in sand, then blend in snow.
	vec3 height_albedo = mix(albedo_grass, albedo_sand, sand_mix);
	height_albedo = mix(height_albedo, albedo_snow, snow_mix);

	// 2. Slope Blending.
	vec3 albedo_slope = sample_world(texture_albedo_slope, world_pos, world_uv_scale).rgb;

	// Calculate slope blend factor (0.0 for flat ground, 1.0 for steep slopes).
	float slope_edge0 = slope_threshold - slope_blend_range * 0.5;
	float slope_edge1 = slope_threshold + slope_blend_range * 0.5;
	float slope_mix_factor = smoothstep(slope_edge1, slope_edge0, world_normal_y);

	// Mix the slope layer over the height-determined base material.
	vec3 terrain_albedo = mix(height_albedo, albedo_slope, slope_mix_factor);

	// 3. Constrained Path Blending.

	// First, determine the final path influence based on the rules.
	// Rule 1: Remove path from slopes. As slope_mix_factor goes to 1, this term goes to 0.
	float final_path_influence = v_path_influence * (1.0 - slope_mix_factor);

	// Rule 2: Fade path out based on world height.
	// The result is 1.0 below start Y, 0.0 above end Y, and fades between them.
	float height_fade = 1.0 - smoothstep(path_fade_start_y, path_fade_end_y, world_pos.y);
	final_path_influence *= height_fade;

	// Now sample the path texture.
	vec3 albedo_path = sample_world(texture_albedo_path, world_pos, world_uv_scale).rgb;

	// Mix the final terrain color with the path color using the constrained influence factor.
	vec3 final_albedo = mix(terrain_albedo, albedo_path, final_path_influence);

	// 4. Final Output.
	ALBEDO = final_albedo * albedo_tint.rgb;
	METALLIC = metallic;
	SPECULAR = specular;
}