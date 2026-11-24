// The character's own look (albedo texture, matte), plus an optional clip that
// hides whatever is above the rim of a cap (the hair), so a snug cap doesn't
// have hair poking through it. Matches the imported StandardMaterial3D.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_col : source_color = vec4(1.0);
uniform float roughness_v = 0.8;
uniform bool clip_on = false;
uniform vec3 clip_centre;           // world: centre of the cap's rim
uniform vec3 clip_normal = vec3(0.0, 1.0, 0.0);   // world: up through the crown
uniform float clip_radius = 0.2;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (clip_on && distance(world_pos, clip_centre) < clip_radius && dot(world_pos - clip_centre, clip_normal) > -0.004) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV) * albedo_col;
	ALBEDO = c.rgb;
	ROUGHNESS = roughness_v;
	METALLIC = 0.0;
}
