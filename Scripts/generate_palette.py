#!/usr/bin/env python3
"""Convert OKLCH colors to Display P3 and generate Xcode asset catalog colorsets.

Pipeline: OKLCH → OKLAB → LMS → XYZ D65 → Linear P3 → Gamma P3

Colorset variants:
  - Main ({Name}.colorset): 500 (dark) / 600 (light) — 60 APCA contrast
  - Alt  ({Name}Alt.colorset): 300 (dark) / 700 (light) — 75 APCA contrast
"""

import json
import math
import os
import sys

# Color palette: name → {level: (L, C, h_degrees)}
PALETTE = {
    "Flamingo":  {"300": (0.89, 0.08, 0),   "500": (0.82, 0.15, 0),   "600": (0.70, 0.27, 0),   "700": (0.58, 0.26, 0)},
    "Coral":     {"300": (0.89, 0.07, 20),  "500": (0.81, 0.13, 20),  "600": (0.69, 0.25, 20),  "700": (0.58, 0.26, 20)},
    "Mahogany":  {"300": (0.89, 0.08, 40),  "500": (0.81, 0.14, 40),  "600": (0.69, 0.24, 40),  "700": (0.58, 0.21, 40)},
    "Pear":      {"300": (0.87, 0.23, 115), "500": (0.79, 0.21, 115), "600": (0.66, 0.17, 115), "700": (0.56, 0.15, 115)},
    "Avocado":   {"300": (0.86, 0.27, 130), "500": (0.78, 0.24, 130), "600": (0.65, 0.21, 130), "700": (0.55, 0.17, 130)},
    "Emerald":   {"300": (0.85, 0.26, 160), "500": (0.77, 0.24, 160), "600": (0.64, 0.20, 160), "700": (0.54, 0.17, 160)},
    "Turquoise": {"300": (0.85, 0.21, 180), "500": (0.77, 0.19, 180), "600": (0.65, 0.16, 180), "700": (0.54, 0.13, 180)},
    "Pelorus":   {"300": (0.87, 0.13, 210), "500": (0.78, 0.18, 210), "600": (0.65, 0.15, 210), "700": (0.55, 0.13, 210)},
    "Steel":     {"300": (0.88, 0.07, 240), "500": (0.79, 0.13, 240), "600": (0.66, 0.20, 240), "700": (0.56, 0.17, 240)},
    "Neon":      {"300": (0.88, 0.06, 270), "500": (0.80, 0.11, 270), "600": (0.68, 0.18, 270), "700": (0.58, 0.25, 270)},
    "Violet":    {"300": (0.89, 0.07, 300), "500": (0.81, 0.12, 300), "600": (0.69, 0.21, 300), "700": (0.59, 0.28, 300)},
    "Orchid":    {"300": (0.90, 0.12, 330), "500": (0.82, 0.21, 330), "600": (0.70, 0.28, 330), "700": (0.59, 0.28, 330)},
}


def oklch_to_p3(L: float, C: float, h_deg: float) -> tuple[float, float, float]:
    """Convert OKLCH to gamma-encoded Display P3 RGB components (0–1)."""
    # OKLCH → OKLAB
    h_rad = math.radians(h_deg)
    a = C * math.cos(h_rad)
    b = C * math.sin(h_rad)

    # OKLAB → LMS (cube-root domain)
    l = L + 0.3963377774 * a + 0.2158037573 * b
    m = L - 0.1055613458 * a - 0.0638541728 * b
    s = L - 0.0894841775 * a - 1.2914855480 * b

    # Cube to recover linear LMS
    L_ = l ** 3
    M_ = m ** 3
    S_ = s ** 3

    # LMS → XYZ D65
    X =  1.2270138511035211 * L_ - 0.5577999806518222 * M_ + 0.2812561489664678 * S_
    Y = -0.0405801784232806 * L_ + 1.1122568696168302 * M_ - 0.0716766786656012 * S_
    Z = -0.0763812845057069 * L_ - 0.4214819784180127 * M_ + 1.5861632204407947 * S_

    # XYZ D65 → linear Display P3
    R_lin =  2.493496911941425  * X - 0.931383617919124 * Y - 0.402710784450717 * Z
    G_lin = -0.829488969561575  * X + 1.762664060318346 * Y + 0.023624685841944 * Z
    B_lin =  0.035845830243784  * X - 0.076172389268042 * Y + 0.956884524007687 * Z

    # Clamp to P3 gamut
    R_lin = max(0.0, min(1.0, R_lin))
    G_lin = max(0.0, min(1.0, G_lin))
    B_lin = max(0.0, min(1.0, B_lin))

    # Apply sRGB/P3 gamma transfer function
    def gamma(c: float) -> float:
        if c <= 0.0031308:
            return 12.92 * c
        return 1.055 * (c ** (1.0 / 2.4)) - 0.055

    return gamma(R_lin), gamma(G_lin), gamma(B_lin)


def make_colorset_json(light_rgb: tuple, dark_rgb: tuple) -> dict:
    """Create Xcode colorset Contents.json with light (universal) and dark variants."""
    def fmt(v: float) -> str:
        return f"{v:.3f}"

    return {
        "colors": [
            {
                "color": {
                    "color-space": "display-p3",
                    "components": {
                        "alpha": "1.000",
                        "blue": fmt(light_rgb[2]),
                        "green": fmt(light_rgb[1]),
                        "red": fmt(light_rgb[0]),
                    },
                },
                "idiom": "universal",
            },
            {
                "appearances": [
                    {"appearance": "luminosity", "value": "dark"}
                ],
                "color": {
                    "color-space": "display-p3",
                    "components": {
                        "alpha": "1.000",
                        "blue": fmt(dark_rgb[2]),
                        "green": fmt(dark_rgb[1]),
                        "red": fmt(dark_rgb[0]),
                    },
                },
                "idiom": "universal",
            },
        ],
        "info": {"author": "xcode", "version": 1},
    }


def generate(output_dir: str) -> None:
    """Generate all colorset directories and JSON files."""
    os.makedirs(output_dir, exist_ok=True)

    # Folder-level Contents.json (no namespace — colors accessible by name directly)
    with open(os.path.join(output_dir, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")

    for name, levels in PALETTE.items():
        # Main variant: 500 (dark) / 600 (light)
        dark_main = oklch_to_p3(*levels["500"])
        light_main = oklch_to_p3(*levels["600"])

        main_dir = os.path.join(output_dir, f"{name}.colorset")
        os.makedirs(main_dir, exist_ok=True)
        with open(os.path.join(main_dir, "Contents.json"), "w") as f:
            json.dump(make_colorset_json(light_main, dark_main), f, indent=2)
            f.write("\n")

        # Alt variant: 300 (dark) / 700 (light)
        dark_alt = oklch_to_p3(*levels["300"])
        light_alt = oklch_to_p3(*levels["700"])

        alt_dir = os.path.join(output_dir, f"{name}Alt.colorset")
        os.makedirs(alt_dir, exist_ok=True)
        with open(os.path.join(alt_dir, "Contents.json"), "w") as f:
            json.dump(make_colorset_json(light_alt, dark_alt), f, indent=2)
            f.write("\n")

        # Print conversion results for verification
        print(f"{name}:")
        print(f"  Main  light(600): P3({light_main[0]:.3f}, {light_main[1]:.3f}, {light_main[2]:.3f})")
        print(f"  Main  dark (500): P3({dark_main[0]:.3f}, {dark_main[1]:.3f}, {dark_main[2]:.3f})")
        print(f"  Alt   light(700): P3({light_alt[0]:.3f}, {light_alt[1]:.3f}, {light_alt[2]:.3f})")
        print(f"  Alt   dark (300): P3({dark_alt[0]:.3f}, {dark_alt[1]:.3f}, {dark_alt[2]:.3f})")

    print(f"\nGenerated {len(PALETTE) * 2} colorsets in {output_dir}")


if __name__ == "__main__":
    output_dir = sys.argv[1] if len(sys.argv) > 1 else "Colors"
    generate(output_dir)
