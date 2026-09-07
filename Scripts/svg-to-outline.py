#!/usr/bin/env python3
"""Flatten an SVG path into the unit-box polylines GlyphOutline uses.

The app draws vendor marks as filled polylines rather than as SVG, because the
notch's glyph is 17pt and a Shape can be tinted, scaled and animated with the
rest of the ring. This turns a real logo into that form once, at build time,
instead of approximating one by hand.

    ./scripts/svg-to-outline.py <name> <file.svg> [more...]

Writes Swift to stdout. Coordinates are normalised into a 0...1 box with the
aspect ratio preserved and the mark centred, which is what makes every vendor's
logo occupy the same optical area.
"""
import math
import re
import sys

# --- path parsing ------------------------------------------------------------

TOKEN = re.compile(r'([MmLlHhVvCcSsQqTtAaZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)')


def tokenize(d):
    for command, number in TOKEN.findall(d):
        yield command if command else float(number)


def arc_points(x0, y0, rx, ry, phi, large, sweep, x, y, steps):
    """SVG endpoint arc → sampled points (F.6.5 of the SVG spec)."""
    if rx == 0 or ry == 0 or (x0 == x and y0 == y):
        return [(x, y)]
    phi = math.radians(phi)
    cos_p, sin_p = math.cos(phi), math.sin(phi)
    dx2, dy2 = (x0 - x) / 2, (y0 - y) / 2
    x1 = cos_p * dx2 + sin_p * dy2
    y1 = -sin_p * dx2 + cos_p * dy2
    rx, ry = abs(rx), abs(ry)
    # Scale the radii up if they are too small to span the endpoints.
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        rx *= math.sqrt(lam)
        ry *= math.sqrt(lam)
    sign = -1 if large == sweep else 1
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    coef = sign * math.sqrt(max(0.0, num / den)) if den else 0.0
    cx1, cy1 = coef * rx * y1 / ry, -coef * ry * x1 / rx
    cx = cos_p * cx1 - sin_p * cy1 + (x0 + x) / 2
    cy = sin_p * cx1 + cos_p * cy1 + (y0 + y) / 2

    def angle(ux, uy, vx, vy):
        dot = ux * vx + uy * vy
        mag = math.hypot(ux, uy) * math.hypot(vx, vy)
        a = math.acos(max(-1.0, min(1.0, dot / mag))) if mag else 0.0
        return -a if ux * vy - uy * vx < 0 else a

    theta = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if not sweep and delta > 0:
        delta -= 2 * math.pi
    elif sweep and delta < 0:
        delta += 2 * math.pi

    out = []
    for i in range(1, steps + 1):
        t = theta + delta * i / steps
        px = cos_p * rx * math.cos(t) - sin_p * ry * math.sin(t) + cx
        py = sin_p * rx * math.cos(t) + cos_p * ry * math.sin(t) + cy
        out.append((px, py))
    return out


def cubic(p0, p1, p2, p3, steps):
    out = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        out.append((
            u**3 * p0[0] + 3 * u*u*t * p1[0] + 3 * u*t*t * p2[0] + t**3 * p3[0],
            u**3 * p0[1] + 3 * u*u*t * p1[1] + 3 * u*t*t * p2[1] + t**3 * p3[1],
        ))
    return out


def quad(p0, p1, p2, steps):
    out = []
    for i in range(1, steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u*u * p0[0] + 2*u*t * p1[0] + t*t * p2[0],
                    u*u * p0[1] + 2*u*t * p1[1] + t*t * p2[1]))
    return out


def flatten(d, curve_steps=14, arc_steps=18):
    """The path as a list of closed polylines, in the SVG's own coordinates."""
    tokens = list(tokenize(d))
    loops, current = [], []
    i = 0
    cursor = (0.0, 0.0)
    start = (0.0, 0.0)
    command = None
    last_control = None

    def take(n):
        nonlocal i
        values = tokens[i:i + n]
        i += n
        return values

    while i < len(tokens):
        if isinstance(tokens[i], str):
            command = tokens[i]
            i += 1
        relative = command.islower()
        c = command.upper()

        if c == 'M':
            x, y = take(2)
            if relative:
                x, y = cursor[0] + x, cursor[1] + y
            if len(current) > 1:
                loops.append(current)
            cursor = start = (x, y)
            current = [cursor]
            command = 'l' if relative else 'L'   # subsequent pairs are lineto
        elif c in 'LT':
            if c == 'L':
                x, y = take(2)
            else:                                 # smooth quadratic
                x, y = take(2)
            if relative:
                x, y = cursor[0] + x, cursor[1] + y
            cursor = (x, y)
            current.append(cursor)
        elif c == 'H':
            x, = take(1)
            cursor = (cursor[0] + x if relative else x, cursor[1])
            current.append(cursor)
        elif c == 'V':
            y, = take(1)
            cursor = (cursor[0], cursor[1] + y if relative else y)
            current.append(cursor)
        elif c in 'CS':
            if c == 'C':
                x1, y1, x2, y2, x, y = take(6)
                if relative:
                    x1, y1 = cursor[0] + x1, cursor[1] + y1
                    x2, y2 = cursor[0] + x2, cursor[1] + y2
                    x, y = cursor[0] + x, cursor[1] + y
            else:
                x2, y2, x, y = take(4)
                if relative:
                    x2, y2 = cursor[0] + x2, cursor[1] + y2
                    x, y = cursor[0] + x, cursor[1] + y
                # Reflection of the previous control point.
                if last_control:
                    x1 = 2 * cursor[0] - last_control[0]
                    y1 = 2 * cursor[1] - last_control[1]
                else:
                    x1, y1 = cursor
            current += cubic(cursor, (x1, y1), (x2, y2), (x, y), curve_steps)
            last_control = (x2, y2)
            cursor = (x, y)
            continue
        elif c == 'Q':
            x1, y1, x, y = take(4)
            if relative:
                x1, y1 = cursor[0] + x1, cursor[1] + y1
                x, y = cursor[0] + x, cursor[1] + y
            current += quad(cursor, (x1, y1), (x, y), curve_steps)
            last_control = (x1, y1)
            cursor = (x, y)
            continue
        elif c == 'A':
            rx, ry, phi, large, sweep, x, y = take(7)
            if relative:
                x, y = cursor[0] + x, cursor[1] + y
            current += arc_points(cursor[0], cursor[1], rx, ry, phi,
                                  int(large), int(sweep), x, y, arc_steps)
            cursor = (x, y)
        elif c == 'Z':
            if len(current) > 1:
                loops.append(current)
            current = []
            cursor = start
        last_control = last_control if c in 'CSQT' else None

    if len(current) > 1:
        loops.append(current)
    return loops


# --- simplification and normalisation ----------------------------------------

def simplify(points, tolerance):
    """Douglas–Peucker, so a 1900-character path is not 900 points of Swift."""
    if len(points) < 3:
        return points
    first, last = points[0], points[-1]
    worst, index = 0.0, 0
    dx, dy = last[0] - first[0], last[1] - first[1]
    span = math.hypot(dx, dy)
    for k in range(1, len(points) - 1):
        px, py = points[k]
        if span:
            d = abs(dy * px - dx * py + last[0] * first[1] - last[1] * first[0]) / span
        else:
            d = math.hypot(px - first[0], py - first[1])
        if d > worst:
            worst, index = d, k
    if worst > tolerance:
        left = simplify(points[:index + 1], tolerance)
        right = simplify(points[index:], tolerance)
        return left[:-1] + right
    return [first, last]


def normalise(loops):
    """Into a 0...1 box, aspect preserved, centred."""
    xs = [p[0] for loop in loops for p in loop]
    ys = [p[1] for loop in loops for p in loop]
    minx, maxx, miny, maxy = min(xs), max(xs), min(ys), max(ys)
    span = max(maxx - minx, maxy - miny) or 1.0
    ox = (1 - (maxx - minx) / span) / 2
    oy = (1 - (maxy - miny) / span) / 2
    return [[((p[0] - minx) / span + ox, (p[1] - miny) / span + oy) for p in loop]
            for loop in loops]


def emit(name, loops):
    print(f"    static let {name}: [[CGPoint]] = [")
    for loop in loops:
        print("        [", end="")
        for k, (x, y) in enumerate(loop):
            if k and k % 4 == 0:
                print("\n         ", end="")
            print(f"CGPoint(x: {x:.4f}, y: {y:.4f}), ", end="")
        print("],")
    print("    ]")


def main():
    args = sys.argv[1:]
    if len(args) < 2 or len(args) % 2:
        sys.exit(__doc__)
    for name, path in zip(args[::2], args[1::2]):
        svg = open(path).read()
        d = " ".join(re.findall(r'\sd="([^"]+)"', svg))
        loops = flatten(d)
        loops = normalise(loops)
        loops = [simplify(loop, 0.004) for loop in loops]
        loops = [loop for loop in loops if len(loop) > 2]
        emit(name, loops)
        total = sum(len(loop) for loop in loops)
        print(f"    // {len(loops)} loop(s), {total} points", file=sys.stderr)


if __name__ == "__main__":
    main()
