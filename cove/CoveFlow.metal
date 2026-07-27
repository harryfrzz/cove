#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// HSV → RGB. Lets a whole card palette be derived from one seeded hue instead
// of shipping a fixed colour table, so every event gets its own combination.
static inline float3 coveHSV(float3 c) {
    float3 rgb = clamp(abs(fmod(c.x * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
                       0.0, 1.0);
    rgb = rgb * rgb * (3.0 - 2.0 * rgb);
    return c.z * mix(float3(1.0), rgb, c.y);
}

// Digits rendered as glass vessels holding purple liquid.
//
// This is a *layer* effect rather than a colour effect specifically so it can
// sample the glyph it is drawing. A colour effect only ever knows the single
// pixel it sits on, which is not enough to tell the edge of a stroke from its
// middle — and without that, none of what makes glass look like glass is
// available. Reading the layer's own alpha over a small disc gives a cheap
// distance field, and that field drives the wall thickness, the bevel, the
// Fresnel rim, and the refraction that bends the liquid near an edge.
//
// `loop` is a 0…1 phase and every wave is an integer harmonic of it, so the
// slosh repeats seamlessly rather than jumping.
[[ stitchable ]]
half4 coveGlassNumber(float2 position, SwiftUI::Layer layer,
                      float2 size, float loop, float level) {
    float2 safeSize = max(size, float2(1.0));
    float tau = 6.2831853;
    float th = tau * loop;

    float coverage = layer.sample(position).a;
    if (coverage < 0.004) {
        return half4(0.0h);
    }

    // Pseudo distance field: average glyph coverage over a ring. Reads ~1 deep
    // inside a stroke and falls toward 0 approaching the outline, which is
    // exactly the gradient a thick glass wall needs.
    const int taps = 12;
    // Scaled to the glyph rather than fixed: a constant pixel wall makes big
    // digits look like thin foil and small ones look solid. Capped so the
    // caller's `maxSampleOffset` stays valid.
    float wall = clamp(safeSize.y * 0.055, 6.0, 16.0);
    float inset = 0.0;
    for (int i = 0; i < taps; ++i) {
        float ang = tau * float(i) / float(taps);
        inset += layer.sample(position + float2(cos(ang), sin(ang)) * wall).a;
    }
    inset /= float(taps);

    // Surface normal from the coverage gradient, so highlights land on the
    // correct side of every stroke rather than uniformly around it.
    const float e = 2.0;
    float gx = layer.sample(position + float2(e, 0.0)).a
             - layer.sample(position - float2(e, 0.0)).a;
    float gy = layer.sample(position + float2(0.0, e)).a
             - layer.sample(position - float2(0.0, e)).a;
    float2 gradient = float2(-gx, -gy);
    float slope = length(gradient);
    float2 normal = slope > 1e-4 ? gradient / slope : float2(0.0);

    // Refraction. Near an edge the wall is steep, so what sits behind it is
    // displaced sideways — the single strongest cue that a shape has real
    // thickness rather than being a flat fill.
    float2 refracted = position + normal * pow(1.0 - inset, 1.5) * 22.0;
    float2 uv = refracted / safeSize;

    // --- the liquid ---
    float wave = sin(uv.x * tau * 2.0 + th * 2.0) * 0.028
               + sin(uv.x * tau * 3.0 - th * 3.0) * 0.016;
    float bob = sin(th) * 0.014;
    float surface = (1.0 - clamp(level, 0.0, 1.0)) + wave + bob;
    float depth = uv.y - surface;

    float aa = 2.0 / safeSize.y;
    float fill = smoothstep(-aa, aa, depth);

    float3 deep    = float3(0.26, 0.07, 0.58);
    float3 shallow = float3(0.60, 0.34, 0.96);
    float3 liquid  = mix(shallow, deep, saturate(depth * 1.4));
    // Meniscus: the bright line fluid draws where it meets a wall.
    liquid += exp(-pow(depth / 0.045, 2.0)) * 0.30;
    // Caustics through the body.
    liquid += sin(uv.x * 30.0 + th * 3.0) * sin(uv.y * 22.0 - th * 2.0) * 0.045 * fill;

    // Above the waterline the digit is empty glass, not a hole.
    float3 emptyGlass = float3(0.87, 0.84, 0.93);
    float3 body = mix(emptyGlass, saturate(liquid), fill);

    // --- the shell ---
    float2 lightDir = normalize(float2(-0.55, -0.83));   // upper left
    float facing = dot(normal, lightDir);

    // Fresnel: grazing angles at the outline reflect most of the light.
    body += pow(saturate(1.0 - inset), 2.2) * 0.45;
    // Specular streak along the lit side of each stroke.
    body += pow(saturate(facing), 10.0) * slope * 5.0;
    // Contact shading on the far side, which is what gives the wall its round.
    body -= pow(saturate(1.0 - inset), 3.0) * saturate(-facing) * 0.28;

    // Empty glass is thinner than filled, so it lets more through.
    float alpha = coverage * mix(0.66, 1.0, fill);
    // Premultiplied, as the effect pipeline expects.
    return half4(half3(saturate(body) * alpha), half(alpha));
}

// Flowing backdrop for one Upcoming card. Three coloured light sources travel
// on independent orbits through a warped space; their falloffs are summed and
// normalised, which is what keeps the boundaries between colours soft rather
// than banded.
//
// Everything that gives a card its character is a seeded uniform rather than a
// constant — hue and how far apart the stops sit, which way and how fast the
// orbits turn, the Lissajous ratio that decides the shape of each path, how
// turbulent the warp is, how tight the blobs are. Sharing one formula and
// varying only the phase, which is where this started, left every card moving
// in visibly the same pattern.
//
// The animation is a true loop. `loop` arrives as a 0…1 phase rather than a
// running clock, and every time-varying term below is an *integer* multiple of
// it — so the state at phase 1 is identical to the state at phase 0 and the
// wrap is invisible. Driving this from wall-clock seconds and wrapping the
// seconds instead, which is what it did first, put a visible jump in the
// motion every time the counter came back around.
//
//   palette: (base hue, hue spread, base saturation, per-stop value step)
//   motion:  (phase, spin, orbit ratio, warp amount)
//   shape:   (blob falloff, orbit radius, base harmonic, hue turns per loop)
[[ stitchable ]]
half4 coveEventFlow(float2 position, half4 currentColor,
                    float2 size, float loop,
                    float4 palette, float4 motion, float4 shape) {
    float2 safeSize = max(size, float2(1.0));
    float2 uv = position / safeSize;
    float aspect = safeSize.x / safeSize.y;
    float2 p = float2(uv.x * aspect, uv.y);

    float baseHue   = palette.x;
    float spread    = palette.y;
    float satBase   = palette.z;
    float valueStep = palette.w;

    float phase = motion.x * 6.2831853;
    float spin  = motion.y;
    float ratio = motion.z;
    float warp  = motion.w;

    float falloff  = shape.x;
    float radius   = shape.y;
    float harmonic = shape.z;
    float hueTurns = shape.w;

    // One turn of the loop. `spin` is ±1, so roughly half the cards run the
    // whole animation — orbits, warp, hue drift — in reverse.
    float th = 6.2831853 * loop * spin;

    // Two octaves of domain warp on the 2nd and 3rd harmonics. The finer one
    // is what stops the motion reading as three discs on rails — the blobs
    // stretch and fold into each other as they pass.
    p += float2(sin(p.y * 3.3 + th * 2.0 + phase),
                cos(p.x * 2.9 - th * 2.0 + phase * 1.6)) * warp;
    p += float2(sin(p.y * 7.1 - th * 3.0 + phase * 2.3),
                cos(p.x * 6.4 + th * 3.0 + phase * 0.8)) * warp * 0.32;

    // Whole turns of the wheel per loop, so the hue lands back where it
    // started. Some cards roll zero and hold their palette.
    float hue = baseHue + loop * hueTurns * spin;

    float3 accum = float3(0.0);
    float total = 0.0;

    for (int i = 0; i < 3; ++i) {
        float fi = float(i);
        // Integer harmonics, so each orbit closes exactly once per loop.
        float a = th * (harmonic + fi) + phase + fi * 2.09;
        // A Lissajous figure, not a circle: `ratio` sets how many vertical
        // swings happen per horizontal one, so one card traces a slow ellipse
        // and the next a figure-eight or a trefoil. Integer, for the same
        // reason — a fractional ratio traces an open curve that never closes.
        float2 centre = float2(0.5 * aspect + cos(a) * (radius - 0.05 * fi),
                               0.5 + sin(a * ratio + fi * 1.7) * (radius * 0.85 - 0.04 * fi));

        float d = distance(p, centre);
        // Falloff sets how defined each blob is. Loose reads as a soft wash,
        // tight as three distinct lights moving past each other.
        float w = 1.0 / (1.0 + falloff * d * d);
        w *= w;

        // `spread` is what makes the combinations genuinely different rather
        // than one palette rotated: a small value keeps a card nearly
        // monochrome, a large one throws the three stops across the wheel.
        float3 stop = coveHSV(float3(fract(hue + fi * spread),
                                     satBase + fi * 0.11,
                                     1.0 - fi * valueStep));
        accum += stop * w;
        total += w;
    }

    float3 color = accum / max(total, 1e-4);

    // Lit top-left corner, matching every other card surface in Cove.
    float sheen = saturate(1.0 - length(uv - float2(0.22, 0.16)) * 1.5);
    color += sheen * sheen * 0.10;

    // Adaptive lift toward white. Not taste — the card's text is Cove's dark
    // ink, and now that saturation and hue are both rolled per card, a card
    // can land on a deep palette. Measuring luma and lifting the dark ones
    // further is what keeps contrast safe across every possible roll.
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = mix(color, float3(1.0), 0.10 + saturate(0.70 - luma) * 0.55);

    return half4(half3(saturate(color)), currentColor.a);
}

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
