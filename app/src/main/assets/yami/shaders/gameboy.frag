// Yami post shader: Pocket — 4-shade green handheld palette
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#endif
uniform sampler2D texture;
uniform vec2 outputSize;   // window size in px
uniform vec2 inputSize;    // game resolution (e.g. 640x480)
uniform vec4 viewRect;     // game picture rect inside the window (x, y, w, h)
uniform float frameCount;
uniform float intensity;   // 0..2, user slider
varying vec2 v_texCoord;

vec2 gamePos() { // position in game pixels, origin bottom-left of the picture
    vec2 px = v_texCoord * outputSize;
    return (px - viewRect.xy) / viewRect.zw * inputSize;
}

void main() {
    vec3 col = texture2D(texture, v_texCoord).rgb;
    float l = dot(col, vec3(0.299, 0.587, 0.114));
    vec3 c0 = vec3(0.06, 0.22, 0.06), c1 = vec3(0.19, 0.38, 0.19), c2 = vec3(0.55, 0.67, 0.06), c3 = vec3(0.61, 0.74, 0.06);
    vec3 pal = l < 0.25 ? c0 : (l < 0.5 ? c1 : (l < 0.75 ? c2 : c3));
    vec2 f = fract(gamePos());
    float grid = mix(1.0, step(0.1, f.x) * step(0.1, f.y) * 0.25 + 0.75, 0.6);
    gl_FragColor = vec4(mix(col, pal * grid, clamp(intensity, 0.0, 1.0)), 1.0);
}
