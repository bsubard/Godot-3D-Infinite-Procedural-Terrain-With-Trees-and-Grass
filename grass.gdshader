shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, unshaded, shadows_disabled;

// Add these uniforms at the top
uniform float camera_fade_start : hint_range(10.0, 500.0) = 50.0;
uniform float camera_fade_length : hint_range(1.0, 200.0) = 25.0;

// Your existing uniforms (color, texture, etc.) will be here
uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color,filter_linear_mipmap,repeat_enable;
uniform float alpha_hash_scale : hint_range(0.0, 2.0, 0.01);
// ... other PBR uniforms

// --- NEW: Wind Effect Uniforms ---
group_uniforms wind_effect;
// A seamless noise texture (like the one you just made)
uniform sampler2D wind_noise;
// The direction the wind waves will travel in the XZ plane
uniform vec2 wind_direction = vec2(1.0, 0.7);
// How fast the waves move
uniform float wind_speed : hint_range(0.0, 5.0) = 0.5;
// How far the grass blades will bend
uniform float wind_strength : hint_range(0.0, 5.0) = 0.2;
// The size/scale of the wind gusts. Larger values = bigger waves.
uniform float wind_scale : hint_range(0.001, 55.0) = 0.5;

// Add this varying
varying vec3 v_world_pos;

void vertex() {
	// 1. Calculate the ORIGINAL world position of the vertex first.
	// This is needed for the fragment shader's fading logic.
	vec3 original_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = original_world_pos; // Pass it to the fragment shader.

	// 2. Get the WORLD POSITION OF THE GRASS BLADE'S BASE (its origin).
	// This is the key change. MODEL_MATRIX[3].xyz holds the position of the instance.
	// This value is the SAME for all vertices of a single blade.
	vec3 instance_world_pos = MODEL_MATRIX[3].xyz;

	// 3. Calculate wind UVs using the INSTANCE position for a consistent result.
	vec2 wind_uv = instance_world_pos.xz * wind_scale;
	wind_uv += TIME * wind_speed * normalize(wind_direction);

	// 4. Sample the noise. Now, `noise_value` will be identical for all vertices in this blade.
	float noise_value = texture(wind_noise, wind_uv).r * 2.0 - 1.0;

	// 5. Create the sway mask from the UVs to keep the base planted. This part is correct.
	float sway_mask = 1.0 - UV.y;

	// 6. Calculate the final offset amount.
	float offset_amount = noise_value * wind_strength * sway_mask;

	// 7. Define the wind's direction in world space.
	vec3 world_wind_dir = vec3(normalize(wind_direction).x, 0.0, normalize(wind_direction).y);

	// 8. Calculate the final position by adding the offset to the original world position.
	// This ensures the sway happens along the world-aligned wind direction.
	vec3 new_world_pos = original_world_pos + (world_wind_dir * offset_amount);

	// 9. Convert the new, offsetted world position back into the model's local space
	// and assign it to VERTEX. This is the final step that moves the vertex.
	VERTEX = (inverse(MODEL_MATRIX) * vec4(new_world_pos, 1.0)).xyz;
}



void fragment() {
	// ... your existing fragment code to set ALBEDO, etc. ...
	vec4 albedo_tex = texture(texture_albedo, UV);
	ALBEDO = albedo.rgb * albedo_tex.rgb;

	// --- NEW FADE LOGIC ---
	// Calculate the distance from the camera (EYE) to this specific pixel
	float dist = distance(CAMERA_POSITION_WORLD, v_world_pos);

	// Calculate the fade amount using smoothstep for a nice curve
	float fade_alpha = smoothstep(camera_fade_start + camera_fade_length, camera_fade_start, dist);

	// Multiply the final alpha by our fade amount
	ALPHA = albedo.a * albedo_tex.a * fade_alpha;

	ALPHA_HASH_SCALE = alpha_hash_scale;
	// For Alpha Hash to work correctly with the fade, you can use this trick
	// It discards more pixels as the object gets farther away
	//if (hash(SCREEN_UV) > ALPHA) {
		//discard;
	//}
	// If you are NOT using Alpha Hash, you would just use:
	//ALPHA = albedo.a * albedo_tex.a * fade_alpha;
}

// A simple hash function for the dithering effect
// (You might need to add this if it wasn't auto-generated)
int hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 443.8975);
    p3 += dot(p3, p3.yzx+19.19);
    return int(fract((p3.x + p3.y) * p3.z)*255.0);
}