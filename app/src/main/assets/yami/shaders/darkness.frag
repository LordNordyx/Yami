// Yami post shader: Darkness — the edges sink into black; deeper blacks, a touch of contrast
#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#endif
uniform sampler2D texture;
uniform vec2 outputSize;   // window size in px
uniform vec2 inputSize;    // game resolution
uniform vec4 viewRect;     // game picture rect inside the window (x, y, w, h)
uniform float frameCount;
uniform float intensity;   // 0..2, user slider
varying vec2 v_texCoord;

void main() {
    vec3 col = texture2D(texture, v_texCoord).rgb;
    vec2 rect0 = viewRect.xy / outputSize;
    vec2 rectS = viewRect.zw / outputSize;
    vec2 local = (v_texCoord - rect0) / rectS;           // 0..1 within the picture
    // deeper blacks: a gentle curve that keeps highlights
    col = mix(col, col * col * (3.0 - 2.0 * col), 0.35 * clamp(intensity, 0.0, 2.0));
    // vignette: an ellipse fitted to the picture, falling to black at the corners
    float r = length(local - 0.5) * 1.42;
    float v = 1.0 - smoothstep(0.55, 1.05, r) * clamp(0.55 * intensity, 0.0, 1.0);
    gl_FragColor = vec4(col * v, 1.0);
}
