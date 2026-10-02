#!/usr/bin/env python3
"""Generates Android and iOS app icons from the master icon."""

import os
from PIL import Image, ImageDraw


def generate_icons(master_path="assets/icon/app_icon.png"):
    master = Image.open(master_path).convert("RGB")
    w, h = master.size

    # Circular mask for round icons
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, w, h), fill=255)
    src_circle = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    src_circle.paste(master, (0, 0), mask)

    # Squircle mask for standard Android launcher icons
    s_mask = Image.new("L", (w, h), 0)
    sdraw = ImageDraw.Draw(s_mask)
    sdraw.rounded_rectangle((0, 0, w, h), radius=int(w * 0.22), fill=255)
    src_squircle = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    src_squircle.paste(master, (0, 0), s_mask)

    # Android legacy mipmaps
    android_res = os.path.join("android", "app", "src", "main", "res")
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }

    for folder, size in densities.items():
        out_dir = os.path.join(android_res, folder)
        os.makedirs(out_dir, exist_ok=True)

        icon = src_squircle.resize((size, size), Image.Resampling.LANCZOS)
        icon.save(os.path.join(out_dir, "ic_launcher.png"), "PNG")

        icon_round = src_circle.resize((size, size), Image.Resampling.LANCZOS)
        icon_round.save(os.path.join(out_dir, "ic_launcher_round.png"), "PNG")

    # Android adaptive foregrounds
    gauge_mask = Image.new("L", (w, h), 0)
    gdraw = ImageDraw.Draw(gauge_mask)
    gdraw.ellipse((20, 20, w - 20, h - 20), fill=255)
    gauge_crop = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gauge_crop.paste(master, (0, 0), gauge_mask)

    fg_densities = {
        "mipmap-mdpi": 108,
        "mipmap-hdpi": 162,
        "mipmap-xhdpi": 216,
        "mipmap-xxhdpi": 324,
        "mipmap-xxxhdpi": 432,
    }
    for folder, size in fg_densities.items():
        fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        gauge_size = int(size * 0.76)
        resized = gauge_crop.resize(
            (gauge_size, gauge_size), Image.Resampling.LANCZOS
        )
        offset = (size - gauge_size) // 2
        fg.paste(resized, (offset, offset), resized)
        out_dir = os.path.join(android_res, folder)
        fg.save(os.path.join(out_dir, "ic_launcher_foreground.png"), "PNG")

    # iOS icons (RGB format required by Apple)
    ios_res = os.path.join(
        "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset"
    )
    ios_icons = [
        ("Icon-App-20x20@1x.png", 20),
        ("Icon-App-20x20@2x.png", 40),
        ("Icon-App-20x20@3x.png", 60),
        ("Icon-App-29x29@1x.png", 29),
        ("Icon-App-29x29@2x.png", 58),
        ("Icon-App-29x29@3x.png", 87),
        ("Icon-App-40x40@1x.png", 40),
        ("Icon-App-40x40@2x.png", 80),
        ("Icon-App-40x40@3x.png", 120),
        ("Icon-App-60x60@2x.png", 120),
        ("Icon-App-60x60@3x.png", 180),
        ("Icon-App-76x76@1x.png", 76),
        ("Icon-App-76x76@2x.png", 152),
        ("Icon-App-83.5x83.5@2x.png", 167),
        ("Icon-App-1024x1024@1x.png", 1024),
    ]

    for filename, size in ios_icons:
        ios_icon = master.resize((size, size), Image.Resampling.LANCZOS)
        ios_icon.save(os.path.join(ios_res, filename), "PNG")

    print("Successfully generated all app icon assets.")


if __name__ == "__main__":
    generate_icons()
