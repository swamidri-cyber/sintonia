#version 440
// ─────────────────────────────────────────────────────────────────────────────
//  grain.frag — ruido de imagen ENCIMA de la película (la ventana del cine es
//  transparente sobre mpv). Mismo grano que cinecrt.frag: 24 cuadros por
//  segundo, granos de ~1,5 px. Sale como puntos claros y oscuros con alfa
//  (premultiplicado), así se ve sobre cualquier video sin tapar nada.
//  Compilar: /usr/lib/qt6/bin/qsb --qt6 -o grain.frag.qsb grain.frag
// ─────────────────────────────────────────────────────────────────────────────
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  res;
    float time;
    float amount;     // fuerza del grano (0..1)
};

const float GRAIN_FPS  = 24.0;
const float GRAIN_SIZE = 1.5;

// azar sin patrones (Dave Hoskins, "hash without sine")
float ghash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 fc = qt_TexCoord0 * res;
    float fr = mod(floor(time * GRAIN_FPS), 997.0);
    vec2 gp = floor(fc / GRAIN_SIZE) + vec2(fr * 37.13, fr * 91.71);
    float n = ghash(gp) + ghash(gp + vec2(511.3, 197.9)) - 1.0;              // -1..1
    float a = abs(n) * amount;
    vec3 c = n > 0.0 ? vec3(a) : vec3(0.0);                  // claro o oscuro
    fragColor = vec4(c, a) * qt_Opacity;
}
