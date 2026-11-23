#!/usr/bin/env python3
"""Rebuild the executable start image and source archive with Smalltalk."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
LIBRARY = ROOT / "Sources/SmalltalkCore/Library"

if __name__ == "__main__":
    subprocess.run(
        ["swift", "run", "st80-bootstrap", *sys.argv[1:], str(LIBRARY)],
        cwd=ROOT,
        check=True,
    )
