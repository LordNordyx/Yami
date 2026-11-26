// Yami post shader: Night light — warm, reduced blue for late sessions
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
    vec3 warm = col * vec3(1.0, 0.86, 0.66);
    gl_FragColor = vec4(mix(col, warm, clamp(intensity, 0.0, 1.5)), 1.0);
}
