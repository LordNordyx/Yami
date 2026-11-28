// Yami post shader: LCD3x — a handheld LCD: every game pixel split into red,
// green and blue stripes with soft gaps between rows (after Gigaherz's LCD3x)
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

const float PI = 3.141592654;

void main() {
    vec2 rect0 = viewRect.xy / outputSize;
    vec2 rectS = viewRect.zw / outputSize;
    vec2 local = (v_texCoord - rect0) / rectS;            // 0..1 within the picture
    vec2 pix = local * inputSize;                          // game pixel coordinates
    // sample the centre of the game pixel: crisp at any scale
    vec2 uv = rect0 + (floor(pix) + 0.5) / inputSize * rectS;
    vec3 col = texture2D(texture, uv).rgb;

    vec2 angle = pix * 2.0 * PI;
    // rows: dark gaps between pixel rows
    float y = (16.0 + sin(angle.y)) / 17.0;
    // columns: red, green, blue stripes across each pixel
    vec3 offsets = PI * vec3(0.5, 0.5 - 2.0 / 3.0, 0.5 - 4.0 / 3.0);
    vec3 x = (4.0 + sin(angle.x + offsets)) / 5.0;
    vec3 lcd = col * y * x * 1.12;                         // brighten back what the mask takes

    gl_FragColor = vec4(mix(col, lcd, clamp(intensity, 0.0, 1.0)), 1.0);
}
