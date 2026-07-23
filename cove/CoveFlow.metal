#include <metal_stdlib>
using namespace metal;

[[ stitchable ]]
half4 coveFlow(float2 position, half4 currentColor, float time, float2 size) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float2 centered = uv - 0.5;
    centered.x *= safeSize.x / safeSize.y;

    float slowTime = time * 0.16;
    float waveA = sin((centered.x * 5.2) + (centered.y * 3.4) + slowTime);
    float waveB = cos((centered.x * -3.0) + (centered.y * 6.1) - (slowTime * 0.72));
    float waveC = sin(length(centered + float2(sin(slowTime) * 0.18,
                                                cos(slowTime * 0.8) * 0.14)) * 12.0
                      - (slowTime * 1.4));

    float caustic = smoothstep(0.2, 1.0, (waveA + waveB + waveC) / 3.0 + 0.48);
    float glow = exp(-5.5 * length(centered - float2(-0.12, 0.08)));
    float edge = 1.0 - smoothstep(0.18, 0.92, length(centered));

    float3 midnight = float3(0.008, 0.018, 0.055);
    float3 ocean = float3(0.025, 0.18, 0.34);
    float3 teal = float3(0.04, 0.52, 0.58);
    float3 color = mix(midnight, ocean, saturate(caustic * 0.72 + glow * 0.35));
    color = mix(color, teal, saturate(glow * caustic * 0.46));
    color *= 0.72 + edge * 0.42;

    return half4(half3(color), currentColor.a);
}
