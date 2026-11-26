// Yami post shader: Vibrance — richer colors and contrast for washed-out games
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
    float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
    float sat = max(col.r, max(col.g, col.b)) - min(col.r, min(col.g, col.b));
    col = mix(vec3(l), col, 1.0 + (1.0 - sat) * 0.45 * intensity);
    col = (col - 0.5) * (1.0 + 0.08 * intensity) + 0.5;
    gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
