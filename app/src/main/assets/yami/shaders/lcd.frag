// Yami post shader: LCD grid — handheld-style pixel grid aligned to game pixels
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
    vec2 f = fract(gamePos());
    float gx = smoothstep(0.0, 0.12, f.x) * smoothstep(1.0, 0.88, f.x);
    float gy = smoothstep(0.0, 0.12, f.y) * smoothstep(1.0, 0.88, f.y);
    float grid = mix(1.0, gx * gy, 0.45 * clamp(intensity, 0.0, 2.0));
    gl_FragColor = vec4(col * grid * (1.0 + 0.12 * intensity), 1.0);
}
