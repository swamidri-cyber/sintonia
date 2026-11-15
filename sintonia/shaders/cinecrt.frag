#version 440
// ─────────────────────────────────────────────────────────────────────────────
//  cinecrt.frag — el filtro CRT del modo cine, completo (el mismo de
//  ~/.config/hypr/shaders/crt.frag: ojo de pez, aberración, halo en lo
//  brillante, barrido, grano, viñeta, sombra del vidrio y el fósforo del
//  canal) MENOS donde la máscara marca una portada: ahí solo se curva, con
//  los colores tal cual. La máscara la arma shell.qml (rectángulos blancos
//  donde están las portadas, cuadro a cuadro) y pasa por la misma curva.
//  Compilar: /usr/lib/qt6/bin/qsb --qt6 -o cinecrt.frag.qsb cinecrt.frag
// ─────────────────────────────────────────────────────────────────────────────
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float keep;       // cuánto color original se cuela en el fósforo (crt.frag: 0.35)
    vec4  dark;       // rampa del fósforo del canal
    vec4  light;
    vec2  res;
    float strength;   // CONFIGURACIÓN → IMAGEN → Filtro de tubo: 1 completo, 0.5 suave, 0 apagado
    float time;       // segundos, para que el grano se mueva
};
layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D mask;

const float CURVE       = 0.025;
const float BEZEL       = 0.008;
const float CORNER      = 0.055;
const float GLASS_SHADE = 0.05;
const float GLASS_DARK  = 0.55;
const float ABERRATION  = 0.0006;
const float GLOW        = 0.55;
const float GLOW_RAD    = 3.0;
const float GLOW_TH     = 0.35;
const float SCANLINES   = 0.04;
const float SCAN_PERIOD = 3.0;
const float GRAIN       = 0.03;
// Ruido de imagen de película: se mueve a 24 cuadros por segundo, granos de
// ~1,5 px, más fuerte en los tonos medios. Va ARRIBA de todo, portadas incluidas.
const float FILM_GRAIN  = 0.13;
const float GRAIN_FPS   = 24.0;
const float GRAIN_SIZE  = 1.5;
const float VIGNETTE    = 0.30;
const vec3  TINT        = vec3(1.03, 1.0, 0.94);

// azar sin patrones (Dave Hoskins, "hash without sine")
float ghash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float glowMask(vec3 c) { return smoothstep(GLOW_TH, 1.0, luma(c)); }
float roundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 px = 1.0 / res;
    // 0. Ojo de pez + vidrio
    vec2 p = qt_TexCoord0 * 2.0 - 1.0;
    p *= (1.0 + CURVE * dot(p, p)) * (1.0 + BEZEL * 2.0);
    vec2 uv = p * 0.5 + 0.5;
    vec2 aspect = vec2(res.x / res.y, 1.0);
    float d = roundBox(p * aspect, aspect, CORNER * 2.0);
    float onePx = 2.0 / res.y;
    if (d > onePx) { fragColor = vec4(0.0, 0.0, 0.0, 1.0) * qt_Opacity; return; }
    float glass = 1.0 - smoothstep(-onePx, onePx, d);
    float edgeShade = glass * mix(1.0 - GLASS_DARK, 1.0, smoothstep(0.0, GLASS_SHADE * 2.0, -d));

    vec4 base = texture(src, uv);
    // (SINTONÍA) lo transparente deja ver lo de abajo (la imagen de fondo, limpia)
    float a = base.a;
    if (a < 0.002) { fragColor = vec4(0.0) * qt_Opacity; return; }
    float m = texture(mask, uv).r;              // 1 = portada (limpia)
    vec2 fromCenter = uv - 0.5;
    vec2 fc = uv * res;                          // píxel de la pantalla

    // 1. Aberración cromática
    vec2 shift = fromCenter * ABERRATION * 2.0;
    vec3 col = vec3(texture(src, uv + shift).r, base.g, texture(src, uv - shift).b);
    // 2. Halo en lo brillante (las letras brillan)
    vec3 glow = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398 + 0.39;
        vec2 dir = vec2(cos(a), sin(a)) * px * GLOW_RAD;
        vec3 s1 = texture(src, uv + dir).rgb;
        vec3 s2 = texture(src, uv + dir * 2.2).rgb;
        float m1 = texture(mask, uv + dir).r, m2 = texture(mask, uv + dir * 2.2).r;
        glow += s1 * glowMask(s1) * 0.65 * (1.0 - m1) + s2 * glowMask(s2) * 0.35 * (1.0 - m2);
    }
    col += glow / 8.0 * GLOW;
    // 3. Barrido   4. Grano
    col *= 1.0 - SCANLINES * (sin(fc.y * 6.28318 / SCAN_PERIOD) * 0.5 + 0.5);
    col += (hash(floor(fc)) - 0.5) * GRAIN;
    // 5. Viñeta   6. Tinte cálido   7. Fósforo del canal
    col *= clamp(1.0 - dot(fromCenter, fromCenter) * VIGNETTE * 2.2, 0.0, 1.0);
    col *= TINT;
    float gl = clamp(luma(col), 0.0, 1.0);
    col = mix(mix(dark.rgb, light.rgb, pow(gl, 0.85)), col, keep);

    col = mix(base.rgb, col, strength);
    col /= a;                                    // sin premultiplicar (vuelve abajo)
    // Portadas: tal cual (solo la curva y la sombra del borde del vidrio)
    col = mix(col, base.rgb, m);
    // 8. Ruido de imagen (SINTONÍA: nunca sobre las portadas ni las imágenes)
    float fr = mod(floor(time * GRAIN_FPS), 997.0);
    vec2 gp = floor(fc / GRAIN_SIZE) + vec2(fr * 37.13, fr * 91.71);
    float n = (ghash(gp) + ghash(gp + vec2(511.3, 197.9)) - 1.0);          // -1..1, más parejo
    float mid = 1.0 - abs(luma(col) * 2.0 - 1.0) * 0.35;  // medios > negros/blancos
    col += n * FILM_GRAIN * mid * strength * (1.0 - m);
    fragColor = vec4(clamp(col * edgeShade, 0.0, 1.0) * a, a) * qt_Opacity;
}
