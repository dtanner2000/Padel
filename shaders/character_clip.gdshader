// The character's own look (albedo texture, matte), plus two optional extras:
// - a clip that hides whatever is above the rim of a cap (the hair), so a snug
//   cap doesn't have hair poking through it;
// - a kit colour: texels matching the character's shirt colour (a hue /
//   saturation / brightness key) are repainted, keeping the cloth's shading.
// Matches the imported StandardMaterial3D otherwise.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform float roughness_v = 0.8;
uniform bool clip_on = false;
uniform vec3 clip_centre;           // world: centre of the cap's rim
uniform vec3 clip_normal = vec3(0.0, 1.0, 0.0);   // world: up through the crown
uniform float clip_radius = 0.2;

uniform bool kit_on = false;
uniform vec4 kit_col : source_color = vec4(0.85, 1.0, 0.1, 1.0);
uniform float key_hue = 0.05;       // 0..1
uniform float key_hue_w = 0.06;     // half-width; >= 0.5 matches any hue
uniform vec2 key_sat = vec2(0.72, 1.01);
uniform float key_val = 0.3;        // darker than this is a shadow line, left alone
uniform float kit_glow = 0.12;      // neon: a little emission

varying vec3 world_pos;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clip_on && distance(world_pos, clip_centre) < clip_radius && dot(world_pos - clip_centre, clip_normal) > -0.004) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV) * albedo_col;
	vec3 col = c.rgb;
	if (kit_on) {
		vec3 srgb = pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.2));
		vec3 hsv = rgb2hsv(srgb);
		float dh = abs(hsv.x - key_hue);
		dh = min(dh, 1.0 - dh);
		float m = key_hue_w >= 0.5 ? 1.0 : 1.0 - smoothstep(key_hue_w * 0.7, key_hue_w, dh);
		m *= smoothstep(key_sat.x - 0.05, key_sat.x + 0.03, hsv.y) * (1.0 - smoothstep(key_sat.y - 0.03, key_sat.y + 0.05, hsv.y));
		m *= smoothstep(key_val - 0.06, key_val + 0.04, hsv.z);
		// the new colour, shaded like the cloth was (folds stay darker)
		vec3 kit_srgb = pow(kit_col.rgb, vec3(1.0 / 2.2)) * clamp(hsv.z / 0.92, 0.3, 1.08);
		vec3 kit_lin = pow(kit_srgb, vec3(2.2));
		col = mix(col, kit_lin, m);
		EMISSION = kit_col.rgb * m * kit_glow;
	}
	ALBEDO = col;
	ROUGHNESS = roughness_v;
	METALLIC = 0.0;
}
