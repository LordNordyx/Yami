// Yami post shader: Scanlines — clean horizontal lines, no curvature
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
    float y = fract(gamePos().y);
    float line = smoothstep(0.0, 0.5, y) * smoothstep(1.0, 0.5, y);
    col *= mix(1.0, 0.55 + 0.6 * line, clamp(intensity, 0.0, 1.5));
    gl_FragColor = vec4(col, 1.0);
}
