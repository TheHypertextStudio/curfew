// The Horizon sky. A port of the fragment shader in
// Documentation/design/horizon-prototype.html, and the GPU twin of
// CurfewKit/Sources/CurfewAtmosphere/HorizonField.swift. Keep the three in step.
//
// Built into the app and the screen saver bundle (never the Swift package), so
// `swift build` and `swift test` stay independent of the Metal toolchain.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace horizon {

constant float H = 0.26;
constant float N = 14.0;

float3 ph(float3 d, float3 g, float3 u, float3 n, float e) {
    if (e > 0.1) return mix(g, d, smoothstep(0.1, 0.55, e));
    if (e > -0.05) return mix(u, g, smoothstep(-0.05, 0.1, e));
    return mix(n, u, smoothstep(-0.4, -0.05, e));
}

// The palette arrives from Swift (`HorizonPalette.shaderTable`) so the CPU
// renderer and the shader share one table: for each of six stops (five ramp
// stops, then the ground), the day, last hour, dusk and night colours.
float3 entry(device const float *table, int stop, int palette) {
    int i = (stop * 4 + palette) * 3;
    return float3(table[i], table[i + 1], table[i + 2]);
}

float3 stopColor(device const float *table, int stop, float e) {
    return ph(entry(table, stop, 0), entry(table, stop, 1),
              entry(table, stop, 2), entry(table, stop, 3), e);
}

float3 ramp(device const float *table, float k, float e) {
    float x = clamp(k, 0.0, 1.0) * 4.0;
    if (x < 1.0) return mix(stopColor(table, 0, e), stopColor(table, 1, e), x);
    if (x < 2.0) return mix(stopColor(table, 1, e), stopColor(table, 2, e), x - 1.0);
    if (x < 3.0) return mix(stopColor(table, 2, e), stopColor(table, 3, e), x - 2.0);
    return mix(stopColor(table, 3, e), stopColor(table, 4, e), x - 3.0);
}

float brightness(float2 uv, float asp, float2 S, float2 M, float2 W, float E) {
    float a = max((uv.y - H) / (1.0 - H), 0.0);
    float rs = length(float2((uv.x - S.x) * asp, uv.y - S.y));
    float rm = length(float2((uv.x - M.x) * asp, uv.y - M.y));
    float low = 1.0 - smoothstep(0.05, 0.6, abs(E));
    return 1.0 - (1.0 - exp(-rs * 2.4) * W.x)
               * (1.0 - exp(-rm * 3.2) * W.y * 0.7)
               * (1.0 - exp(-a * 3.2) * mix(0.34, 0.9, low));
}

}  // namespace horizon

/// SwiftUI colour effect. `position` is in points with y down; the scene
/// frame has y up. `scale` is pixels per point, so anti-aliasing and band
/// edges are measured in device pixels exactly as the prototype measures them.
[[ stitchable ]] half4 horizonSky(
    float2 position, half4 color, float2 size, float2 S, float2 M, float2 W,
    float E, float PH, float MO, float scale, device const float *table, int count
) {
    if (count < 72) return half4(0.0h, 0.0h, 0.0h, 1.0h);
    using namespace horizon;
    float2 uv = float2(position.x / size.x, 1.0 - position.y / size.y);
    float asp = size.x / size.y;
    float pixel = 1.0 / max(scale, 1.0);
    float2 uvx = float2((position.x + pixel) / size.x, uv.y);
    float2 uvy = float2(uv.x, 1.0 - (position.y + pixel) / size.y);

    float L = brightness(uv, asp, S, M, W, E);
    float Lx = brightness(uvx, asp, S, M, W, E);
    float Ly = brightness(uvy, asp, S, M, W, E);

    float x = L * N + PH;
    float fw = (abs(Lx - L) + abs(Ly - L)) * N;
    float w = clamp(fw * 1.1, 0.0, 0.45);
    float kq = floor(x) + (w > 0.0 ? smoothstep(1.0 - w, 1.0, fract(x)) : 0.0);
    float k = (kq - PH) / N;

    float3 c = ramp(table, k, E + (k - 0.5) * 0.24);
    float aa = 1.5 / (size.y * max(scale, 1.0));

    float rs = length(float2((uv.x - S.x) * asp, uv.y - S.y));
    float disc = (1.0 - smoothstep(0.05 - aa, 0.05 + aa, rs)) * step(0.01, W.x);
    c = mix(c, ramp(table, 1.0, E + 0.12) * 1.02 + 0.03, disc);

    float2 q = float2((uv.x - M.x) * asp, uv.y - M.y) / 0.04;
    float mq = dot(q, q);
    float lit = step(0.0, q.x * sin(MO) - sqrt(max(1.0 - mq, 0.0)) * cos(MO));
    float moon = (1.0 - smoothstep(1.0 - aa * 40.0, 1.0 + aa * 40.0, mq)) * smoothstep(0.0, 0.25, W.y);
    c = mix(c, mix(float3(0.2, 0.22, 0.42), float3(0.93, 0.92, 0.97), lit), moon);

    float3 g = stopColor(table, 5, E);
    float3 outColor = uv.y < H ? g : c;
    return half4(half3(outColor), 1.0h);
}
