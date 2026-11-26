// Yami post shader: FXAA — smooths jagged edges of bilinear/bicubic upscales
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

float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
void main() {
    vec2 p = 1.0 / outputSize;
    vec3 nw = texture2D(texture, v_texCoord + vec2(-p.x, -p.y)).rgb;
    vec3 ne = texture2D(texture, v_texCoord + vec2(p.x, -p.y)).rgb;
    vec3 sw = texture2D(texture, v_texCoord + vec2(-p.x, p.y)).rgb;
    vec3 se = texture2D(texture, v_texCoord + vec2(p.x, p.y)).rgb;
    vec3 m  = texture2D(texture, v_texCoord).rgb;
    float lnw = luma(nw), lne = luma(ne), lsw = luma(sw), lse = luma(se), lm = luma(m);
    float lmin = min(lm, min(min(lnw, lne), min(lsw, lse)));
    float lmax = max(lm, max(max(lnw, lne), max(lsw, lse)));
    vec2 dir = vec2(-((lnw + lne) - (lsw + lse)), ((lnw + lsw) - (lne + lse)));
    float red = max((lnw + lne + lsw + lse) * 0.03125, 1.0 / 128.0);
    float rcp = 1.0 / (min(abs(dir.x), abs(dir.y)) + red);
    dir = clamp(dir * rcp, -8.0, 8.0) * p * clamp(intensity, 0.0, 1.5);
    vec3 a = 0.5 * (texture2D(texture, v_texCoord + dir * (1.0/3.0 - 0.5)).rgb + texture2D(texture, v_texCoord + dir * (2.0/3.0 - 0.5)).rgb);
    vec3 b = a * 0.5 + 0.25 * (texture2D(texture, v_texCoord - dir * 0.5).rgb + texture2D(texture, v_texCoord + dir * 0.5).rgb);
    float lb = luma(b);
    gl_FragColor = vec4((lb < lmin || lb > lmax) ? a : b, 1.0);
}
