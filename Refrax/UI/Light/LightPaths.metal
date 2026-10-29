#include <metal_stdlib>
using namespace metal;

// Draws LightPath values packed by LightPacking (LightPacking.swift). Every pixel sums the
// light of every lit segment around it: a Gaussian halo in the path's color, a narrower
// Gaussian core in white, a soft spot at the lit tip, and, on the last segment of a
// dispersing path, two more bands turned a few degrees to either side in neighboring
// hues. A path's pulse brightens the halo and core around one place along its length.
// The sum becomes premultiplied color at the end.

namespace light {

// Layout of the float array; mirrors the constants in LightPacking.
constant int header = 2;
constant int pathStride = 24;
constant int segmentStride = 8;

// Angle between the center band and each outer band at full dispersion (6°).
constant float fanAngle = 0.104719755;
// Halo brightness relative to the core.
constant float glowGain = 0.7;
// Brightness of the halo around the tip spot.
constant float spotHaloGain = 0.8;
// Smallest radius of the tip spot's white center, in points.
constant float minimumSpotRadius = 4.0;
// Beyond this many sigmas a Gaussian adds nothing visible.
constant float reach = 4.0;

// exp(-(d/σ)²): 1 at the center, e⁻¹ at σ, 2% at 2σ.
static inline float gaussian(float d, float sigma) {
    float x = d / sigma;
    return exp(-x * x);
}

static inline float2 rotate(float2 v, float angle) {
    float s = sin(angle), c = cos(angle);
    return float2(v.x * c - v.y * s, v.x * s + v.y * c);
}

// Light reaching `position` from every packed path, as premultiplied RGBA.
static half4 shade(float2 position, device const float *data, int count) {
    if (count < header) {
        return half4(0);
    }
    int pathCount = int(data[0]);
    int segmentBase = header + pathCount * pathStride;
    if (count < segmentBase) {
        return half4(0);
    }

    float3 tint = 0;   // color-weighted light
    float energy = 0;  // total light

    for (int p = 0; p < pathCount; p++) {
        device const float *path = data + header + p * pathStride;
        int firstSegment = int(path[0]);
        int segmentCount = int(path[1]);
        float litLength = path[3];
        float intensity = path[7];
        if (litLength <= 0 || intensity <= 0) {
            continue;
        }
        float3 baseColor = float3(path[4], path[5], path[6]);
        // The core's full width spans about ±1.2σ, the halo's full width ±2σ.
        float coreSigma = max(path[8] * 0.6, 0.5);
        float glowSigma = max(path[9] * 0.25, 0.5);
        float dispersion = path[10];
        float spotScale = max(path[11], 0.01);
        float3 lowColor = float3(path[12], path[13], path[14]);
        float3 highColor = float3(path[16], path[17], path[18]);
        float pulseCenter = path[20];
        float pulseSigma = max(path[21], 0.5);
        float pulseGain = path[22];
        float spotRadius = max(coreSigma * 4.0, minimumSpotRadius) * spotScale;
        float spotHaloSigma = glowSigma * 2.0 * spotScale;
        float cutoff = max(glowSigma, spotHaloSigma) * reach;

        for (int s = 0; s < segmentCount; s++) {
            device const float *segment = data + segmentBase + (firstSegment + s) * segmentStride;
            float2 a = float2(segment[0], segment[1]);
            float start = segment[4];
            float segmentLength = segment[5];
            float2 direction = float2(segment[6], segment[7]);
            // Segments come in path order, so the first unlit one ends the path.
            float lit = min(litLength - start, segmentLength);
            if (lit < 0) {
                break;
            }
            bool last = s == segmentCount - 1;
            bool holdsTip = last || lit < segmentLength;
            // Dispersion opens the last segment into three bands.
            float fan = last ? dispersion * fanAngle : 0;
            int bandCount = fan > 0 ? 3 : 1;

            for (int b = 0; b < bandCount; b++) {
                float angle = b == 0 ? 0 : (b == 1 ? -fan : fan);
                float3 bandColor = b == 0 ? baseColor : (b == 1 ? lowColor : highColor);
                float weight = (b == 0 ? 1.0 : dispersion) * intensity;
                float2 bandDirection = rotate(direction, angle);

                // Distance to the lit part of the band: project onto it, clamp to [0, lit].
                float2 toPosition = position - a;
                float t = clamp(dot(toPosition, bandDirection), 0.0, lit);
                float distance = length(toPosition - bandDirection * t);
                float spotDistance = holdsTip ? length(toPosition - bandDirection * lit) : cutoff;
                if (min(distance, spotDistance) > cutoff) {
                    continue;
                }

                // The pulse scales the beam by how close this point's place along the path is to its center.
                float pulse = 1.0 + pulseGain * gaussian(start + t - pulseCenter, pulseSigma);
                float glow = gaussian(distance, glowSigma) * glowGain * pulse;
                float core = gaussian(distance, coreSigma) * pulse;
                float spotHalo = holdsTip ? gaussian(spotDistance, spotHaloSigma) * spotHaloGain : 0;
                float spotCore = holdsTip ? gaussian(spotDistance, spotRadius) : 0;

                float colored = (glow + spotHalo) * weight;
                float white = (core + spotCore) * weight;
                tint += bandColor * colored + float3(1.0) * white;
                energy += colored + white;
            }
        }
    }

    if (energy <= 0) {
        return half4(0);
    }
    // Light saturates softly toward opaque; the color is the energy-weighted mean,
    // premultiplied by the alpha it produced.
    float alpha = 1.0 - exp(-energy);
    float3 rgb = (tint / energy) * alpha;
    return half4(half3(rgb), half(alpha));
}

} // namespace light

// SwiftUI colorEffect entry point: `position` is in the layer's points, top-left origin.
[[stitchable]] half4 lightPaths(float2 position, half4 color, device const float *data, int count) {
    return light::shade(position, data, count);
}

// Runs the same shading over a texture so a test can read the pixels back without a window.
kernel void lightPathsProbe(
    device const float *data [[buffer(0)]],
    constant int &count [[buffer(1)]],
    texture2d<half, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    output.write(light::shade(float2(gid) + 0.5, data, count), gid);
}
