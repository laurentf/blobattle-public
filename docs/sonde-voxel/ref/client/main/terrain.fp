#version 140

in mediump vec3 var_normal;
in highp vec3 var_pos;

out vec4 out_fragColor;

float hash2(vec2 p)
{
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
	vec3 n = normalize(var_normal);
	vec3 soil = vec3(0.47, 0.34, 0.30);
	vec3 rim = vec3(0.98, 0.66, 0.42);
	float depth_cell = 2.0;
	vec3 base;
	vec2 uv;
	if (n.z > 0.9) {
		// front face; a slightly tilted normal marks the rim band
		base = n.y > 0.02 ? rim : soil * (0.72 + 0.28 * clamp(var_pos.y / 256.0, 0.0, 1.0));
		uv = var_pos.xy;
		n = vec3(0.0, 0.0, 1.0);
	} else if (abs(n.y) > 0.5) {
		base = n.y > 0.0 ? rim : soil * 0.6;
		uv = vec2(var_pos.x, var_pos.z / depth_cell);
	} else {
		base = soil * 0.92;
		uv = vec2(var_pos.y, var_pos.z / depth_cell);
	}
	vec2 cell = floor(uv);
	base *= 0.92 + 0.12 * hash2(cell);
	vec2 f = fract(uv);
	vec2 w = fwidth(uv);
	vec2 g = smoothstep(vec2(0.0), w * 1.5, min(f, 1.0 - f));
	float grid = min(g.x, g.y);
	float fade = clamp(1.0 - max(w.x, w.y) * 2.5, 0.0, 1.0);
	base *= mix(1.0, mix(0.82, 1.0, grid), fade);
	vec3 light = normalize(vec3(-0.25, 0.8, 0.6));
	float l = 0.72 + 0.28 * max(dot(n, light), 0.0);
	out_fragColor = vec4(base * l, 1.0);
}
