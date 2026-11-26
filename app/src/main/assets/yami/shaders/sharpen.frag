// Yami post shader: Sharpen (CAS) — contrast-adaptive sharpening after upscaling
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
    vec2 p = 1.0 / outputSize;
    vec3 a = texture2D(texture, v_texCoord + vec2(0.0, -p.y)).rgb;
    vec3 b = texture2D(texture, v_texCoord + vec2(-p.x, 0.0)).rgb;
    vec3 c = texture2D(texture, v_texCoord).rgb;
    vec3 d = texture2D(texture, v_texCoord + vec2(p.x, 0.0)).rgb;
    vec3 e = texture2D(texture, v_texCoord + vec2(0.0, p.y)).rgb;
    vec3 mn = min(min(min(a, b), min(d, e)), c);
    vec3 mx = max(max(max(a, b), max(d, e)), c);
    vec3 amp = clamp(min(mn, 2.0 - mx) / max(mx, 1e-4), 0.0, 1.0);
    vec3 w = -sqrt(amp) / mix(8.0, 5.0, clamp(intensity * 0.5, 0.0, 1.0));
    vec3 col = (c + (a + b + d + e) * w) / (1.0 + 4.0 * w);
    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
