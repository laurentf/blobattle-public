#version 140

in mediump vec3 var_normal;
in highp vec3 var_pos;

out vec4 out_fragColor;

uniform mediump sampler2D texture0;

uniform fs_uniforms
{
    mediump vec4 map_size;
    mediump vec4 fog;
    mediump vec4 fog_band;
    mediump vec4 surface;
    mediump vec4 soil;
    mediump vec4 rock;
    mediump vec4 wood;
    mediump vec4 leaves;
    mediump vec4 steel;
};

vec3 colour_of(float k)
{
    if (k < 1.5) return surface.rgb;
    if (k < 2.5) return soil.rgb;
    if (k < 3.5) return rock.rgb;
    if (k < 4.5) return wood.rgb;
    if (k < 5.5) return leaves.rgb;
    return steel.rgb;
}

float hash2(vec2 p)
{
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void main()
{
    vec3 n = normalize(var_normal);
    vec2 inside = floor(n.z > 0.9 ? var_pos.xy : var_pos.xy - n.xy * 0.5);
    float k = floor(texture(texture0, (inside + 0.5) / map_size.xy).r * 255.0 + 0.5);
    vec3 material = colour_of(k);
    float depth_cell = 2.0;
    vec3 base;
    vec2 uv;
    if (n.z > 0.9) {
        base = material * (0.8 + 0.2 * clamp(var_pos.y / map_size.y, 0.0, 1.0));
        uv = var_pos.xy;
        n = vec3(0.0, 0.0, 1.0);
    } else if (abs(n.y) > 0.5) {
        base = n.y > 0.0 ? min(material * 1.25, vec3(1.0)) : material * 0.6;
        uv = vec2(var_pos.x, var_pos.z / depth_cell);
    } else {
        base = material * 0.92;
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
    float haze = fog.w * clamp(1.0 - (var_pos.y - fog_band.x) / fog_band.y, 0.0, 1.0);
    out_fragColor = vec4(mix(base * l, fog.rgb, haze), 1.0);
}
