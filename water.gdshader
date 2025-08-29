shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Your original material properties
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform ivec2 albedo_texture_size;
uniform float point_size : hint_range(0.1, 128.0, 0.1);
uniform float roughness : hint_range(0.0, 1.0);
uniform sampler2D texture_metallic : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_texture_channel;
uniform sampler2D texture_roughness : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform float specular : hint_range(0.0, 1.0, 0.01);
uniform float metallic : hint_range(0.0, 1.0, 0.01);
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0);
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

// New transparency and foam properties
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, repeat_disable, filter_nearest;
uniform float depth_fade_distance : hint_range(0.0, 10.0) = 1.0;
uniform float absorbance : hint_range(0.0, 10.0) = 2.0;
uniform vec3 shallow_color : source_color = vec3(0.22, 0.66, 1.0);
uniform vec3 deep_color : source_color = vec3(0.0, 0.25, 0.45);
uniform float foam_amount : hint_range(0.0, 2.0) = 0.2;
uniform vec3 foam_color : source_color = vec3(1);
uniform sampler2D foam_noise : hint_default_white;

// Wave properties
uniform sampler2D wave_texture;
uniform float wave_scale = 4.0;
uniform float height_scale = 0.15;
uniform float wave_speed : hint_range(0.0, 0.2) = 0.015;

varying float wave_height;
varying vec3 uv_world_pos;

vec3 screen(vec3 base, vec3 blend){
	return 1.0 - (1.0 - base) * (1.0 - blend);
}

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;

	// Vertex displacement for waves
	uv_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wave_height = texture(wave_texture, uv_world_pos.xz / wave_scale + TIME * wave_speed*0.2).r;
	VERTEX.y += wave_height * height_scale;
}

void fragment() {
	vec2 base_uv = UV;

	// YOUR ANIMATED LAYERS SYSTEM (keeping this!)
	// Create multiple moving layers with different speeds and directions
	vec2 uv1 = base_uv + TIME * vec2(0.01, 0.005);
	vec2 uv2 = base_uv + TIME * vec2(-0.008, 0.012);
	vec2 uv3 = base_uv + TIME * vec2(0.006, -0.009);

	// Sample multiple times and blend
	vec3 normal1 = texture(texture_normal, uv1).rgb;
	vec3 normal2 = texture(texture_normal, uv2).rgb;
	vec3 normal3 = texture(texture_normal, uv3).rgb;

	// Blend the normals (convert from [0,1] to [-1,1] range first)
	normal1 = normal1 * 2.0 - 1.0;
	normal2 = normal2 * 2.0 - 1.0;
	normal3 = normal3 * 2.0 - 1.0;

	vec3 blended_normal = normalize(normal1 + normal2 * 0.5 + normal3 * 0.3);
	vec3 final_normal = blended_normal * 0.5 + 0.5; // Convert back to [0,1]

	// Do the same for albedo
	vec4 albedo1 = texture(texture_albedo, uv1);
	vec4 albedo2 = texture(texture_albedo, uv2);
	vec3 blended_albedo = mix(albedo1.rgb, albedo2.rgb, 0.5);

	// Your original material properties
	float metallic_tex = dot(texture(texture_metallic, base_uv), metallic_texture_channel);
	vec4 roughness_texture_channel = vec4(1.0, 0.0, 0.0, 0.0);
	float roughness_tex = dot(texture(texture_roughness, base_uv), roughness_texture_channel);

	// NEW TRANSPARENCY AND FOAM SYSTEM
	// Depth texture magic
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV, 0.0).r;
  	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 world = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float depth_texture_y = world.y / world.w;
	float vertex_y = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y;
	float vertical_depth = vertex_y - depth_texture_y;

	// Changes the color of geometry behind it as the water gets deeper
	float depth_fade_blend = exp(-vertical_depth / depth_fade_distance);
	depth_fade_blend = clamp(depth_fade_blend, 0.0, 1.0);

	// Makes the water more transparent as it gets more shallow
	float alpha_blend = -vertical_depth * absorbance;
	alpha_blend = clamp(1.0 - exp(alpha_blend), 0.0, 1.0);

	// Small layer of foam
	float foam_blend = clamp(1.0 - (vertical_depth / foam_amount), 0.0, 1.0);
	vec3 foam = foam_blend * foam_color;

	// COMBINE EVERYTHING
	// Mix water depth colors
	vec3 water_color = mix(deep_color, shallow_color, depth_fade_blend);
	// Add foam
	water_color = screen(water_color, foam);
	// Blend with your animated albedo texture
	vec3 final_albedo = mix(water_color, albedo.rgb * blended_albedo, 0.3); // Adjust 0.3 to control texture visibility

	// Set final outputs
	if (FRONT_FACING) {
		ALPHA = alpha_blend; // Use calculated alpha for front faces
	} else {
		ALPHA = 1.0;
	}

	ALBEDO = final_albedo;
	METALLIC = metallic_tex * metallic;
	SPECULAR = specular;
	ROUGHNESS = roughness_tex * roughness;
	NORMAL_MAP = final_normal;
	NORMAL_MAP_DEPTH = normal_scale;
}