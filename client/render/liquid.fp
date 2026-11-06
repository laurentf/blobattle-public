#version 140

in mediump float var_shade;

out vec4 out_fragColor;

uniform fs_uniforms
{
    mediump vec4 tint;
};

void main()
{
    out_fragColor = vec4(tint.rgb * var_shade, 1.0);
}
