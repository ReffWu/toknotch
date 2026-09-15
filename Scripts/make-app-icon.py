#!/usr/bin/env python3
"""Generate the TokNotch app icon and write every size the AppIcon.appiconset
and the website need.

The icon is *composed here*, not hand-drawn: a blue squircle (diagonal
gradient) with the app's own SideNotchShape silhouette welded to its right
edge, a Claude-coral usage ring inside it, a thin rim light, and a uniform
concentric near-black frame. A small payback
"13.4x" bubble sits on the blue face — it is part of the mark.

Requires: Pillow, and Google Chrome (the bubble + its text are rendered by
headless Chrome for crisp SF Pro and a clean tangential tail, then composited).

Usage:  python3 Scripts/make-app-icon.py
Writes: Sources/Assets.xcassets/AppIcon.appiconset/*.png (+ Contents.json)
        ../artifacts/toknotch/assets/icon.png, icon.webp   (if that repo is present)
"""
import math, subprocess, base64, json, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
APPICON = os.path.join(REPO, "Sources/Assets.xcassets/AppIcon.appiconset")
ARTIFACTS = os.path.abspath(os.path.join(REPO, "..", "..", "artifacts", "toknotch", "assets"))
DOCS_ASSETS = os.path.join(REPO, "docs", "assets")
NOTCH_PNG = os.path.join(HERE, "notch-silhouette.png")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
S = 2048

def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i]-a[i])*t)) for i in range(len(a)))

def rr_mask(size, box, radius):
    k = 4
    m = Image.new("L", tuple(s*k for s in size), 0)
    ImageDraw.Draw(m).rounded_rectangle(tuple(v*k for v in box), radius=radius*k, fill=255)
    return m.resize(size, Image.LANCZOS)

def diag_gradient(size, c0, c1):
    w, h = size
    g = Image.new("RGB", size); px = g.load(); den = (w-1)+(h-1)
    for y in range(h):
        for x in range(w):
            px[x, y] = lerp(c0, c1, (x+y)/den)
    return g

# ---- geometry: blue stays generous, frame added outward ----
BLUE = (176, 176, 1872, 1872); BLUE_R = 392
F = 132
OUTER = (BLUE[0]-F, BLUE[1]-F, BLUE[2]+F, BLUE[3]+F); OUTER_R = BLUE_R + F
BW = BLUE[2] - BLUE[0]

_notch0 = Image.open(NOTCH_PNG).convert("RGBA")
_k = BW / 1664.0
NOTCH = _notch0.resize((round(_notch0.width*_k), round(_notch0.height*_k)), Image.LANCZOS)
NW, NH = NOTCH.size


NAME = "TOKNOTCH"
SIGNATURE = "REFFWU"
FONT_PATH = "/System/Library/Fonts/Optima.ttc"
FONT_SIZE = 46
TRACKING = 16
ENGRAVING = (128, 128, 134, 255)


def ring_point(distance, box, radius):
    """A point on the frame's centre line, `distance` along it clockwise from
    the top middle, and the direction of travel there in degrees."""
    x0, y0, x1, y1 = box
    width, height = x1 - x0 - 2 * radius, y1 - y0 - 2 * radius
    arc = math.pi * radius / 2
    segments = [
        ("line", (x0 + radius + width / 2, y0), (x1 - radius, y0), width / 2),
        ("arc", (x1 - radius, y0 + radius), -90, 0, arc),
        ("line", (x1, y0 + radius), (x1, y1 - radius), height),
        ("arc", (x1 - radius, y1 - radius), 0, 90, arc),
        ("line", (x1 - radius, y1), (x0 + radius, y1), width),
        ("arc", (x0 + radius, y1 - radius), 90, 180, arc),
        ("line", (x0, y1 - radius), (x0, y0 + radius), height),
        ("arc", (x0 + radius, y0 + radius), 180, 270, arc),
        ("line", (x0 + radius, y0), (x0 + radius + width / 2, y0), width / 2),
    ]
    distance %= sum(segment[-1] for segment in segments)
    for segment in segments:
        if distance <= segment[-1]:
            share = distance / segment[-1]
            if segment[0] == "line":
                (ax, ay), (bx, by) = segment[1], segment[2]
                return ax + (bx - ax) * share, ay + (by - ay) * share, math.degrees(math.atan2(by - ay, bx - ax))
            (cx, cy), start, end = segment[1], segment[2], segment[3]
            angle = math.radians(start + (end - start) * share)
            return cx + radius * math.cos(angle), cy + radius * math.sin(angle), math.degrees(angle) + 90
        distance -= segment[-1]
    raise ValueError("distance outside the frame")


def engrave(canvas, text, position, color, upright):
    """Letters set along the frame's rounded corner, like an engraving on a
    watch case. `upright` runs them the other way round so text on the lower
    half is not upside down."""
    k = 2
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE * k)
    box = (OUTER[0] + F / 2, OUTER[1] + F / 2, OUTER[2] - F / 2, OUTER[3] - F / 2)
    radius = (OUTER_R + BLUE_R) / 2
    perimeter = 2 * (box[2] - box[0] - 2 * radius) + 2 * (box[3] - box[1] - 2 * radius) + 2 * math.pi * radius
    widths = [font.getlength(ch) / k for ch in text]
    total = sum(widths) + TRACKING * (len(text) - 1)
    direction = -1 if upright else 1
    cursor = position * perimeter - direction * total / 2
    layer = Image.new("RGBA", (S * k, S * k), (0, 0, 0, 0))
    for ch, width in zip(text, widths):
        x, y, angle = ring_point(cursor + direction * width / 2, box, radius)
        if upright:
            angle += 180
        side = FONT_SIZE * 2 * k
        glyph = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        ImageDraw.Draw(glyph).text((side / 2, side / 2), ch, font=font, fill=color, anchor="mm")
        glyph = glyph.rotate(-angle, resample=Image.BICUBIC)
        layer.alpha_composite(glyph, (int(x * k - side / 2), int(y * k - side / 2)))
        cursor += direction * (width + TRACKING)
    return Image.alpha_composite(canvas, layer.resize((S, S), Image.LANCZOS))


def build_base(frame_rgb, c0, c1, rim_a, engraving):
    cv = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    fmask = rr_mask((S, S), OUTER, OUTER_R)
    cv.paste(Image.new("RGBA", (S, S), (*frame_rgb, 255)), (0, 0), fmask)

    bmask = rr_mask((S, S), BLUE, BLUE_R)
    grad = diag_gradient((128, 128), c0, c1).resize((S, S), Image.BICUBIC).convert("RGBA")
    cv.paste(grad, (0, 0), bmask)

    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).ellipse((BLUE[0]-300, BLUE[1]-500, BLUE[0]+BW*0.7, BLUE[1]+BW*0.55),
                               fill=(255, 255, 255, 36))
    hl = hl.filter(ImageFilter.GaussianBlur(200))
    hm = Image.new("RGBA", (S, S), (0, 0, 0, 0)); hm.paste(hl, (0, 0), bmask)
    cv = Image.alpha_composite(cv, hm)

    nx = BLUE[2] - NW; ny = (S - NH) // 2
    nl = Image.new("RGBA", (S, S), (0, 0, 0, 0)); nl.alpha_composite(NOTCH, (nx, ny))
    nc = Image.new("RGBA", (S, S), (0, 0, 0, 0)); nc.paste(nl, (0, 0), bmask)
    cv = Image.alpha_composite(cv, nc)

    ring = Image.new("RGBA", (S, S), (0, 0, 0, 0)); rd = ImageDraw.Draw(ring)
    cx, cy = nx + NW*0.52, ny + NH*0.5
    r, st = 120*_k, 36*_k
    bb = (cx-r, cy-r, cx+r, cy+r)
    rd.ellipse(bb, outline=(255, 255, 255, 46), width=round(st))
    cf, ct = (0xE8, 0x93, 0x6B), (0xC9, 0x55, 0x30)
    for i in range(240):
        rd.arc(bb, -90 + 285*(i/240), -90 + 285*((i+1)/240),
               fill=lerp(cf, ct, i/240)+(255,), width=round(st))
    dr = 24*_k
    rd.ellipse((cx-dr, cy-dr, cx+dr, cy+dr), fill=(255, 255, 255, 235))
    rc = Image.new("RGBA", (S, S), (0, 0, 0, 0)); rc.paste(ring, (0, 0), bmask)
    cv = Image.alpha_composite(cv, rc)

    rim = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(BLUE, radius=BLUE_R, outline=(255, 255, 255, rim_a), width=4)
    cv = Image.alpha_composite(cv, rim)
    cv = engrave(cv, NAME, 0.875, engraving, False)
    cv = engrave(cv, SIGNATURE, 0.375, engraving, True)

    cv = Image.composite(cv, Image.new("RGBA", (S, S), (0, 0, 0, 0)), fmask)
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh.paste(Image.new("RGBA", (S, S), (0, 0, 0, 85)), (0, 0), fmask)
    sh = sh.filter(ImageFilter.GaussianBlur(42)).transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -20))
    return Image.alpha_composite(sh, cv)          # 2048 RGBA


def _bubble_path(W, H, R, T, span):
    mY, half = H/2, span/2; tip = half*0.17
    return (f"M {R} 3 H {W-R} A {R} {R} 0 0 1 {W} {R+3} V {mY-half} "
            f"C {W} {mY-half*0.38}, {W+T*0.46} {mY-tip*2.3}, {W+T-tip} {mY-tip} "
            f"Q {W+T} {mY}, {W+T-tip} {mY+tip} "
            f"C {W+T*0.46} {mY+tip*2.3}, {W} {mY+half*0.38}, {W} {mY+half} "
            f"V {H-R-3} A {R} {R} 0 0 1 {W-R} {H-3} H {R} A {R} {R} 0 0 1 3 {H-R-3} "
            f"V {R+3} A {R} {R} 0 0 1 {R} 3 Z")


def with_bubble(base_2048, shadow_op):
    """Composite the 13.4x bubble (headless-Chrome rendered) onto a 2048 base."""
    tmp_icon = os.path.join(HERE, "_iconbase_tmp.png")
    base_2048.save(tmp_icon)
    b64 = base64.b64encode(open(tmp_icon, "rb").read()).decode()
    os.remove(tmp_icon)

    blue_l = BLUE[0] / 2                     # @1024 space
    notch_l = (BLUE[2] - NW) / 2
    body_left = round(blue_l + 22)
    T = 34
    W, H, R, font, xf = 486, 372, 82, 200, 120
    avail = notch_l - 16 - T - body_left
    if avail < W:
        s = avail / W
        W, H, R, font, xf = round(avail), round(H*s), round(R*s), round(font*s), round(xf*s)
    top = (1024 - H) // 2
    d = _bubble_path(W, H, R, T, min(72, H*0.42))
    html = f"""<!DOCTYPE html><meta charset="UTF-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Display","PingFang SC",sans-serif;background:transparent}}
.s{{position:relative;width:1024px;height:1024px}} .s>img{{width:100%;height:100%;display:block}}
.b{{position:absolute;left:{body_left}px;top:{top}px;filter:drop-shadow(0 20px 40px rgba(0,0,0,{shadow_op}))}}
.b svg{{display:block;overflow:visible}}
.n{{position:absolute;left:0;top:0;width:{W}px;height:{H}px;display:flex;align-items:center;justify-content:center;
  font-size:{font}px;font-weight:700;line-height:1;letter-spacing:-.02em;color:#D97757}}
.n i{{font-style:normal;font-size:{xf}px;font-weight:600;opacity:.72;margin-left:5px}}
</style><body>
<div class="s"><img src="data:image/png;base64,{b64}">
<div class="b"><svg width="{W+T+8}" height="{H}" viewBox="0 0 {W+T+8} {H}">
<path d="{d}" fill="#0a0c0e" stroke="rgba(255,255,255,0.18)" stroke-width="2.5"/></svg>
<div class="n">13.4<i>&times;</i></div></div></div>
"""
    htmlp = os.path.join(HERE, "_icon_tmp.html")
    outp = os.path.join(HERE, "_icon_tmp.png")
    open(htmlp, "w").write(html)
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--force-device-scale-factor=2", "--default-background-color=00000000",
                    "--window-size=1024,1024", f"--screenshot={outp}", f"file://{htmlp}"],
                   capture_output=True)
    result = Image.open(outp).convert("RGBA").copy()      # 2048
    os.remove(htmlp); os.remove(outp)
    return result


SIZES = [16, 32, 128, 256, 512]   # base points; each also @2x
BUBBLE_MIN_PT = 128               # <=32pt renders as a smudge with the bubble -> use the clean mark

def slice_appicon(master_bubble, master_clean, suffix):
    for pt in SIZES:
        src = master_bubble if pt >= BUBBLE_MIN_PT else master_clean
        for scale in (1, 2):
            px = pt * scale
            name = f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}{suffix}.png"
            src.resize((px, px), Image.LANCZOS).save(os.path.join(APPICON, name))


def write_contents():
    images = []
    for pt in SIZES:
        for scale in (1, 2):
            images.append({"idiom": "mac", "size": f"{pt}x{pt}", "scale": f"{scale}x",
                           "filename": f"icon_{pt}x{pt}{'@2x' if scale == 2 else ''}.png"})
    json.dump({"images": images, "info": {"version": 1, "author": "make-app-icon.py"}},
              open(os.path.join(APPICON, "Contents.json"), "w"), indent=2)


def main():
    dark_base = build_base((26, 26, 28), (0x3E, 0x7B, 0xFA), (0x2E, 0x40, 0x8E), 70, ENGRAVING)
    dark = with_bubble(dark_base, 0.5)

    # Small sizes (<=32pt) drop the bubble - it is an unreadable smudge there.
    slice_appicon(dark, dark_base.resize((1024, 1024), Image.LANCZOS), "")
    write_contents()
    print("wrote AppIcon.appiconset")

    # website & docs: 512 png + webp of the dark mark (used on both light/dark pages)
    if os.path.isdir(ARTIFACTS):
        dark.resize((512, 512), Image.LANCZOS).save(os.path.join(ARTIFACTS, "icon.png"))
        try:
            dark.resize((512, 512), Image.LANCZOS).save(os.path.join(ARTIFACTS, "icon.webp"),
                                                        "WEBP", quality=90, method=6)
        except Exception as e:
            print("webp skipped:", e)
        print("wrote", ARTIFACTS)
    else:
        print("artifacts repo not found at", ARTIFACTS, "- skipped website assets")

    if os.path.isdir(DOCS_ASSETS):
        dark.resize((512, 512), Image.LANCZOS).save(os.path.join(DOCS_ASSETS, "icon.png"))
        try:
            dark.resize((512, 512), Image.LANCZOS).save(os.path.join(DOCS_ASSETS, "icon.webp"),
                                                        "WEBP", quality=90, method=6)
        except Exception as e:
            pass
        print("wrote", DOCS_ASSETS)


if __name__ == "__main__":
    main()
