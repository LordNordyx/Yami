// Yami post shader: CRT — scanlines, aperture mask, soft glow, gentle curvature
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

vec2 curve(vec2 uv, float k) {
    uv = uv * 2.0 - 1.0;
    vec2 off = abs(uv.yx) / vec2(6.0, 5.0);
    uv = uv + uv * off * off * k;
    return uv * 0.5 + 0.5;
}
void main() {
    vec2 rect0 = viewRect.xy / outputSize;
    vec2 rectS = viewRect.zw / outputSize;
    vec2 local = (v_texCoord - rect0) / rectS;           // 0..1 within picture
    vec2 cl = curve(local, 0.6 * intensity);
    if (cl.x < 0.0 || cl.x > 1.0 || cl.y < 0.0 || cl.y > 1.0) { gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0); return; }
    vec2 uv = rect0 + cl * rectS;
    vec3 col = texture2D(texture, uv).rgb;
    // glow: cheap 4-tap blur added back
    vec2 px = 1.5 / outputSize;
    vec3 glow = (texture2D(texture, uv + vec2(px.x, 0.0)).rgb + texture2D(texture, uv - vec2(px.x, 0.0)).rgb +
                 texture2D(texture, uv + vec2(0.0, px.y)).rgb + texture2D(texture, uv - vec2(0.0, px.y)).rgb) * 0.25;
    col = mix(col, max(col, glow), 0.35);
    // scanlines locked to game rows
    float row = cl.y * inputSize.y;
    float scan = 0.5 + 0.5 * cos(6.2831853 * row);
    col *= mix(1.0, 0.62 + 0.38 * scan, clamp(intensity, 0.0, 1.5));
    // aperture grille
    float m = mod(floor(v_texCoord.x * outputSize.x), 3.0);
    vec3 mask = m < 1.0 ? vec3(1.0, 0.82, 0.82) : (m < 2.0 ? vec3(0.82, 1.0, 0.82) : vec3(0.82, 0.82, 1.0));
    col *= mix(vec3(1.0), mask, 0.6 * clamp(intensity, 0.0, 1.0));
    // vignette + brightness compensation
    vec2 v = cl * (1.0 - cl.yx);
    col *= pow(v.x * v.y * 15.0, 0.12);
    gl_FragColor = vec4(col * 1.18, 1.0);
}
