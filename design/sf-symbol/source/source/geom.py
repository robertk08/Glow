import math

def add(a, b): return (a[0] + b[0], a[1] + b[1])
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def mul(a, s): return (a[0] * s, a[1] * s)
def dist(a, b): return math.hypot(b[0] - a[0], b[1] - a[1])
def cross(a, b): return a[0] * b[1] - a[1] * b[0]
def dot(a, b): return a[0] * b[0] + a[1] * b[1]

def unit(v):
    m = math.hypot(*v)
    return (v[0] / m, v[1] / m)

def perp(v):           # 90 deg CCW in y-up space
    return (-v[1], v[0])

def polar(deg):        # direction from "straight down", rotated toward +x
    r = math.radians(deg)
    return (math.sin(r), -math.cos(r))

def f(n):
    return ("%.3f" % n).rstrip('0').rstrip('.')

def pt(p):             # emit in SVG space (y flipped)
    return "%s %s" % (f(p[0]), f(-p[1]))

def rounded_polygon(pts, r):
    """Path for a polygon with corner radius r (scalar or per-vertex list)."""
    n = len(pts)
    radii = r if isinstance(r, (list, tuple)) else [r] * n
    corners = []
    for i in range(n):
        p_prev, p, p_next = pts[(i - 1) % n], pts[i], pts[(i + 1) % n]
        v1, v2 = unit(sub(p_prev, p)), unit(sub(p_next, p))
        ang = math.acos(max(-1.0, min(1.0, dot(v1, v2))))
        if ang < 1e-6 or abs(ang - math.pi) < 1e-6:
            corners.append((p, p, 0.0, 0))
            continue
        t = radii[i] / math.tan(ang / 2.0)
        t = min(t, dist(p, p_prev) / 2.0, dist(p, p_next) / 2.0)
        rr = t * math.tan(ang / 2.0)
        a, b = add(p, mul(v1, t)), add(p, mul(v2, t))
        # travelling prev -> p -> next: left turn (CCW on screen) => sweep 0
        sweep = 0 if cross(mul(v1, -1), v2) > 0 else 1
        corners.append((a, b, rr, sweep))
    d = ["M %s" % pt(corners[0][0])]
    for i in range(n):
        a, b, rr, sweep = corners[i]
        if rr > 1e-6:
            d.append("A %s %s 0 0 %d %s" % (f(rr), f(rr), sweep, pt(b)))
        nxt = corners[(i + 1) % n][0]
        d.append("L %s" % pt(nxt))
    d.append("Z")
    return " ".join(d)

def poly_bbox(pts, pad=0.0):
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    return (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)

def capsule(a, b, w):
    """Stroke segment with round caps, as a filled stadium."""
    h = w / 2.0
    u = unit(sub(b, a)); p = mul(perp(u), h)
    pts = [add(a, p), add(b, p), sub(b, p), sub(a, p)]
    return rounded_polygon(pts, h), poly_bbox([a, b], h)

def offset_polygon(pts, d):
    """Offset a convex polygon inward by d (positive = shrink)."""
    n = len(pts)
    area = sum(cross(pts[i], pts[(i + 1) % n]) for i in range(n)) / 2.0
    sgn = 1.0 if area > 0 else -1.0     # CCW -> inward normal is left of edge dir
    lines = []
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        u = unit(sub(b, a))
        nrm = mul(perp(u), sgn)          # points inward
        lines.append((add(a, mul(nrm, d)), u))
    out = []
    for i in range(n):
        p1, u1 = lines[(i - 1) % n]
        p2, u2 = lines[i]
        den = cross(u1, u2)
        t = cross(sub(p2, p1), u2) / den
        out.append(add(p1, mul(u1, t)))
    return out

def hollow_polygon(pts, r, w):
    """Outline (stroked) polygon: outer contour + reversed inner contour."""
    inner = offset_polygon(pts, w)
    outer_d = rounded_polygon(pts, r)
    rl = r if isinstance(r, (list, tuple)) else [r] * len(pts)
    ri = list(reversed([max(x - w, 0.6) for x in rl]))
    ri = ri[-1:] + ri[:-1]
    inner_d = rounded_polygon(list(reversed(inner)), ri)
    return outer_d + " " + inner_d, poly_bbox(pts)
