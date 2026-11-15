#version 440
// ─────────────────────────────────────────────────────────────────────────────
//  tvstatic.frag — estática de televisor y barras de color (modo cine).
//  Se dibuja ENCIMA de la interfaz: alpha = cuánto tapa.
//    noise = 0→1 estática (nieve con bandas que ruedan)
//    bars  = 0→1 barras de color SMPTE, con un poco de nieve encima
//  Compilar después de editar:
//    /usr/lib/qt6/bin/qsb --qt6 -o tvstatic.frag.qsb tvstatic.frag
// ─────────────────────────────────────────────────────────────────────────────
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    float time;
    float noise;
    float bars;
    vec2  res;
};

float hash(vec2 p) {
    p = fract(p * vec2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

vec3 smpte(vec2 uv) {
    // 7 barras arriba, franja de castillo y el pie con negros
    if (uv.y < 0.67) {
        int i = int(floor(uv.x * 7.0));
        vec3 c[7] = vec3[7](vec3(0.75), vec3(0.75, 0.75, 0.0), vec3(0.0, 0.75, 0.75), vec3(0.0, 0.75, 0.0),
                            vec3(0.75, 0.0, 0.75), vec3(0.75, 0.0, 0.0), vec3(0.0, 0.0, 0.75));
        return c[clamp(i, 0, 6)];
    }
    if (uv.y < 0.75) {
        int i = int(floor(uv.x * 7.0));
        vec3 c[7] = vec3[7](vec3(0.0, 0.0, 0.75), vec3(0.07), vec3(0.75, 0.0, 0.75), vec3(0.07),
                            vec3(0.0, 0.75, 0.75), vec3(0.07), vec3(0.75));
        return c[clamp(i, 0, 6)];
    }
    float x = uv.x;
    if (x < 0.18) return vec3(0.0, 0.13, 0.3);
    if (x < 0.36) return vec3(1.0);
    if (x < 0.54) return vec3(0.2, 0.0, 0.42);
    return vec3(0.07);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 px = floor(uv * res / 2.0);                       // nieve de 2 px
    float n = hash(px + floor(time * 60.0) * vec2(17.0, 31.0));
    // bandas que ruedan hacia arriba, como una antena mal puesta
    float roll = 0.75 + 0.25 * sin((uv.y + time * 0.9) * 22.0);
    float snow = n * roll;
    float scan = 0.85 + 0.15 * sin(uv.y * res.y * 3.14159);

    vec3 col = vec3(snow) * scan;
    float a = noise;
    if (bars > 0.0) {
        // barras con un temblor horizontal y algo de nieve
        vec2 b = uv;
        b.x += (hash(vec2(floor(uv.y * 90.0), floor(time * 24.0))) - 0.5) * 0.012 * (1.0 - bars * 0.6);
        vec3 bc = smpte(b) * scan + (n - 0.5) * 0.18;
        col = mix(col, bc, bars);
        a = max(a, bars);
    }
    fragColor = vec4(col * a, a) * qt_Opacity;             // premultiplicado
}
