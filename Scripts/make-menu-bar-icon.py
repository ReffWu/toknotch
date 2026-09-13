#!/usr/bin/env python3
"""Draws TokNotch's menu bar icon.

A MacBook screen with the notch hanging from its top edge and three rings in
the notch: what TokNotch puts on the screen, drawn at the size of the menu bar
it sits in. A template image, so macOS tints it for light and dark bars.

Drawn twice. The 2x has real rings. The 1x puts every edge on a whole pixel and
turns the rings into square cut-outs, because an 18-pixel ring has no hole.

    python3 Scripts/make-menu-bar-icon.py
"""
import json
import os
import subprocess
import tempfile

def f(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")

def circle(cx, cy, r):
    """A closed circle as four cubic segments."""
    k = 0.5523 * r
    return (f"M{f(cx)} {f(cy-r)}C{f(cx+k)} {f(cy-r)} {f(cx+r)} {f(cy-k)} {f(cx+r)} {f(cy)}"
            f"C{f(cx+r)} {f(cy+k)} {f(cx+k)} {f(cy+r)} {f(cx)} {f(cy+r)}"
            f"C{f(cx-k)} {f(cy+r)} {f(cx-r)} {f(cy+k)} {f(cx-r)} {f(cy)}"
            f"C{f(cx-r)} {f(cy-k)} {f(cx-k)} {f(cy-r)} {f(cx)} {f(cy-r)}Z")

def svg(body):
    return ('<svg width="18" height="18" viewBox="0 0 18 18" fill="none" '
            'xmlns="http://www.w3.org/2000/svg">' + body + "</svg>")

RASTERIZE = r'''
import AppKit
let args = CommandLine.arguments
let image = NSImage(contentsOfFile: args[1])!
let pixels = Int(args[3])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 18, height: 18)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
'''

def write_imageset(folder, name, one_x_svg, two_x_svg):
    """A template imageset with a separately drawn 1x and 2x.

    PNG rather than the SVG itself so the 1x can be its own drawing: at 18
    pixels a ring or a 1.5pt stroke on a half-point centre is mush, and the
    pixel grid needs lines and cut-outs placed for it."""
    path = os.path.join(folder, name + ".imageset")
    os.makedirs(path, exist_ok=True)
    for existing in os.listdir(path):
        os.remove(os.path.join(path, existing))
    with tempfile.TemporaryDirectory() as tmp:
        script = os.path.join(tmp, "rasterize.swift")
        open(script, "w").write(RASTERIZE)
        for scale, source in ((1, one_x_svg), (2, two_x_svg)):
            src = os.path.join(tmp, f"{scale}.svg")
            open(src, "w").write(source)
            subprocess.run(["swift", script, src, os.path.join(path, f"{name}@{scale}x.png"), str(18 * scale)],
                           check=True)
    contents = json.dumps({
        "images": [
            {"filename": f"{name}@1x.png", "idiom": "universal", "scale": "1x"},
            {"filename": f"{name}@2x.png", "idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"},
    }, indent=2)
    with open(os.path.join(path, "Contents.json"), "w") as file:
        file.write(contents + "\n")

def notch(x0, x1, top, y0, y1, flare, corner):
    """The notch: flush with the edge above it, curling into it at both ends."""
    fl, cr = flare, corner
    return (f"M{f(x0-fl)} {f(top)}L{f(x1+fl)} {f(top)}L{f(x1+fl)} {f(y0)}"
            f"C{f(x1+fl*0.45)} {f(y0)} {f(x1)} {f(y0+fl*0.55)} {f(x1)} {f(y0+fl)}"
            f"L{f(x1)} {f(y1-cr)}C{f(x1)} {f(y1-cr*0.45)} {f(x1-cr*0.45)} {f(y1)} {f(x1-cr)} {f(y1)}"
            f"L{f(x0+cr)} {f(y1)}C{f(x0+cr*0.45)} {f(y1)} {f(x0)} {f(y1-cr*0.45)} {f(x0)} {f(y1-cr)}"
            f"L{f(x0)} {f(y0+fl)}C{f(x0)} {f(y0+fl*0.55)} {f(x0-fl*0.45)} {f(y0)} {f(x0-fl)} {f(y0)}Z")

def two_x():
    rings = "".join(circle(x, 7.4, 1.7) + circle(x, 7.4, 0.8) for x in (5.9, 9.0, 12.1))
    return svg('<rect x="1.25" y="3.75" width="15.5" height="11" rx="2.5" stroke="black" stroke-width="1.5"/>'
               f'<path fill-rule="evenodd" d="{notch(3.0, 15.0, 3.25, 4.5, 10.25, 1.0, 2.25)}{rings}" fill="black"/>')

def one_x():
    holes = "".join(f"M{x} 6h2v2h-2Z" for x in (5, 8, 11))
    return svg('<rect x="1.5" y="4.5" width="15" height="10" rx="2" stroke="black" stroke-width="1"/>'
               f'<path fill-rule="evenodd" d="{notch(3.0, 15.0, 4.0, 5.0, 10.0, 1.0, 1.5)}{holes}" fill="black"/>')

if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    write_imageset(os.path.join(root, "Sources", "Assets.xcassets"), "MenuBarIcon", one_x(), two_x())
    print("wrote Sources/Assets.xcassets/MenuBarIcon.imageset")
