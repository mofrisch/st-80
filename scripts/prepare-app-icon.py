#!/usr/bin/env python3
"""Export the macOS AppIcon catalog from a square PNG using built-in sips."""

import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Square PNG, at least 1024 pixels wide")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    dimensions = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(source)],
        check=True, capture_output=True, text=True,
    ).stdout
    width = int(re.search(r"pixelWidth: (\d+)", dimensions).group(1))
    height = int(re.search(r"pixelHeight: (\d+)", dimensions).group(1))
    if width != height or width < 1024:
        parser.error("Source must be square and at least 1024 × 1024 pixels.")

    catalog = ROOT / "Sources/Smalltalk80/Assets.xcassets"
    iconset = catalog / "AppIcon.appiconset"
    iconset.mkdir(parents=True, exist_ok=True)
    images = []
    for points in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            pixels = points * scale
            filename = f"AppIcon-{points}@{scale}x.png"
            subprocess.run(
                ["sips", "-s", "format", "png", "-z", str(pixels), str(pixels), str(source), "--out", str(iconset / filename)],
                check=True, capture_output=True,
            )
            images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": filename})
    info = {"author": "xcode", "version": 1}
    (catalog / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
    (iconset / "Contents.json").write_text(json.dumps({"images": images, "info": info}, indent=2) + "\n")
    print(f"Exported {len(images)} icon sizes to {iconset}")


if __name__ == "__main__":
    main()
