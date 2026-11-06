#version 140

in mediump vec3 var_normal;
in mediump vec3 var_local;
in mediump vec3 var_lnormal;

out vec4 out_fragColor;

uniform fs_uniforms
{
	mediump vec4 tint;
};

void main()
{
	vec3 n = normalize(var_normal);
	vec3 light = normalize(vec3(-0.35, 0.55, 0.75));
	float d = dot(n, light);
	float band = d > 0.45 ? 1.0 : (d > -0.05 ? 0.8 : 0.62);
	// voxel edges: cells span [i - 0.5, i + 0.5] in x and z, [j, j + 1] in y
	vec3 g3 = vec3(fract(var_local.x + 0.5), fract(var_local.y), fract(var_local.z + 0.5));
	vec3 an = abs(var_lnormal);
	vec2 f = an.x > 0.5 ? g3.yz : (an.y > 0.5 ? g3.xz : g3.xy);
	vec2 uv = an.x > 0.5 ? var_local.yz : (an.y > 0.5 ? var_local.xz : var_local.xy);
	vec2 w = fwidth(uv);
	vec2 e = smoothstep(vec2(0.0), w * 1.2, min(f, 1.0 - f));
	float edge = mix(0.86, 1.0, min(e.x, e.y));
	out_fragColor = vec4(tint.rgb * band * edge + vec3(0.06 * tint.w * max(d, 0.0)), 1.0);
}
