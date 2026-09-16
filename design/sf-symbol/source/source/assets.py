"""Separated, 5x-scale artwork: fixture and light as independent, aligned shapes."""
import os, math
from geom import *
from movinghead import build

SCALE = 5.0
PAD = 1.2          # design units of breathing room, scaled with everything else
ARC_KEEP = (2, 3, 4)   # x-rotation and the two flags must not be scaled

def scale_path(d, s, tx=0.0, ty=0.0):
    """Scale, then translate. Arc radii scale only; rotation and flags pass through."""
    out, toks, i = [], d.split(), 0
    argc = {'M': 2, 'L': 2, 'A': 7, 'Z': 0}
    for_x = {'M': (0,), 'L': (0,), 'A': (5,)}
    for_y = {'M': (1,), 'L': (1,), 'A': (6,)}
    while i < len(toks):
        cmd = toks[i]; n = argc[cmd]; args = toks[i + 1:i + 1 + n]; i += 1 + n
        vals = []
        for j, a in enumerate(args):
            if cmd == 'A' and j in ARC_KEEP:
                vals.append(a)
            else:
                v = float(a) * s
                if j in for_x.get(cmd, ()): v += tx
                elif j in for_y.get(cmd, ()): v += ty
                vals.append(f(v))
        out.append(" ".join([cmd] + vals))
    return " ".join(out)

def viewbox(bb, s=SCALE, pad=PAD):
    x0, y0, x1, y1 = bb
    return ((x0 - pad) * s, (-y1 - pad) * s, (x1 - x0 + 2*pad) * s, (y1 - y0 + 2*pad) * s)

def svg(box, body, title=""):
    x, y, w, h = box
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" '
            'viewBox="%s %s %s %s" fill="currentColor" fill-rule="evenodd">%s\n%s\n</svg>\n'
            % (f(w), f(h), f(x), f(y), f(w), f(h),
               ("\n <title>%s</title>" % title) if title else "", body))

def path(d, s=SCALE, attrs=""):
    return ' <path%s d="%s"/>' % (attrs, scale_path(d, s))

def apex(meta):
    """Where the two beam edges meet — the natural origin for an outward animation."""
    sL, sR, dL, dR = meta['sL'], meta['sR'], meta['dL'], meta['dR']
    den = cross(dL, dR)
    if abs(den) < 1e-9:
        return meta['mouth']
    t = cross(sub(sR, sL), dR) / den
    return add(sL, mul(dL, t))

def bands(meta, k=3, gap=0.16):
    """The cone sliced into segments that read as light travelling outward."""
    sL, sR, dL, dR, span, w = (meta['sL'], meta['sR'], meta['dL'], meta['dR'],
                               meta['span'], meta['w'])
    L = lambda t: add(sL, mul(dL, span * t))
    R = lambda t: add(sR, mul(dR, span * t))
    step, out = 1.0 / k, []
    for i in range(k):
        a, b = i * step + gap * step / 2, (i + 1) * step - gap * step / 2
        quad = [L(a), L(b), R(b), R(a)]
        r = min(w * 0.55, dist(L(a), L(b)) * 0.34)
        out.append(rounded_polygon(quad, r))
    return out

def emit(outdir, p=None, w_outline=4.6, w_fill=6.2):
    os.makedirs(outdir, exist_ok=True)
    (fx_o, lt_o), bb_o, meta = build(w_outline, False, p)
    (fx_f, lt_f), bb_f, meta_f = build(w_fill, True, p)
    hollow = dict(p or {}, beam='hollow')
    (_, lt_h), _, _ = build(w_outline, False, hollow)

    bb = (min(bb_o[0], bb_f[0]), min(bb_o[1], bb_f[1]),
          max(bb_o[2], bb_f[2]), max(bb_o[3], bb_f[3]))
    box = viewbox(bb)
    P = lambda ds, a="": "\n".join(path(d, SCALE, a) for d in ds)

    files = {
        "fixture.svg":        svg(box, P(fx_o), "moving head — fixture, outline"),
        "fixture.fill.svg":   svg(box, P(fx_f), "moving head — fixture, filled"),
        "head.svg":           svg(box, P(fx_f[:1]), "moving head — head only"),
        "head.outline.svg":   svg(box, P(fx_o[:1]), "moving head — head only, outline"),
        "yoke.svg":           svg(box, P(fx_f[1:]), "moving head — yoke only"),
        "yoke.outline.svg":   svg(box, P(fx_o[1:]), "moving head — yoke only, outline"),
        "light.svg":          svg(box, P(lt_f), "moving head — light"),
        "light.outline.svg":  svg(box, P(lt_h), "moving head — light, outline"),
        "light.bands.svg":    svg(box, "\n".join(
                                  path(d, SCALE, ' id="band-%d"' % (i + 1))
                                  for i, d in enumerate(bands(meta_f))),
                                  "moving head — light, banded"),
        "symbol.svg":         svg(box, P(fx_o) + "\n" + P(lt_o), "moving head"),
        "symbol.outline.svg": svg(box, P(fx_o) + "\n" + P(lt_h),
                                  "moving head — outline throughout"),
        "symbol.fill.svg":    svg(box, P(fx_f) + "\n" + P(lt_f), "moving head, filled"),
    }
    # layered: two addressable groups, light anchored at the cone apex
    ax, ay = apex(meta_f)
    ox, oy = ax * SCALE - box[0], -ay * SCALE - box[1]
    layered = (' <g id="fixture">\n%s\n </g>\n'
               ' <g id="light" opacity="0.55" style="transform-box:view-box;'
               'transform-origin:%spx %spx">\n%s\n </g>'
               % (P(fx_f), f(ox), f(oy), P(lt_f)))
    files["layered.svg"] = svg(box, layered, "moving head — layered")

    readme = ("# %s\n\n"
              "All files share one viewBox, so they stack with no positioning:\n\n"
              "    viewBox=\"%s\"   (%s x %s px at 5x)\n\n"
              "Light animation origin (cone apex), measured from the top-left of the\n"
              "viewBox - use it as transform-origin with transform-box: view-box:\n\n"
              "    %s px  %s px\n\n"
              "- fixture.svg / fixture.fill.svg - yoke + head\n"
              "- head.svg / yoke.svg (+ .outline) - the two split apart\n"
              "- light.svg / light.outline.svg / light.bands.svg - the beam only\n"
              "- symbol.svg, symbol.outline.svg, symbol.fill.svg - assembled\n"
              "- layered.svg - both, as #fixture and #light, origin already set\n"
              % (os.path.basename(outdir),
                 " ".join(f(v) for v in box), f(box[2]), f(box[3]), f(ox), f(oy)))
    files["README.md"] = readme
    for name, data in files.items():
        open(os.path.join(outdir, name), "w").write(data)
    return box, (ox, oy), sorted(files)

if __name__ == "__main__":
    TILT = dict(tilt=15.0, cone=20.0)
    for name, p in (("straight", None), ("tilt", TILT)):
        box, org, names = emit("artwork-5x/" + name, p)
        print("%-9s viewBox %s  apex(%s, %s)  %d files"
              % (name, " ".join(f(v) for v in box), f(org[0]), f(org[1]), len(names)))
    print(names)


# ---- square, centred layers for Icon Composer ---------------------------

def icon_layers(outdir, p=None, canvas=1024.0, frac=0.58, w_outline=4.6, w_fill=6.2):
    """Each layer on the same square canvas, explicit black, no currentColor."""
    os.makedirs(outdir, exist_ok=True)
    (fx_o, lt_o), bb_o, _ = build(w_outline, False, p)
    (fx_f, lt_f), bb_f, _ = build(w_fill, True, p)
    (_, lt_h), _, _ = build(w_outline, False, dict(p or {}, beam='hollow'))
    bb = (min(bb_o[0], bb_f[0]), min(bb_o[1], bb_f[1]),
          max(bb_o[2], bb_f[2]), max(bb_o[3], bb_f[3]))
    s = frac * canvas / (bb[3] - bb[1])
    cx, cy = (bb[0] + bb[2]) / 2.0, -(bb[1] + bb[3]) / 2.0
    tx, ty = canvas / 2.0 - cx * s, canvas / 2.0 - cy * s

    def doc(ds, title):
        body = "\n".join(' <path d="%s"/>' % scale_path(d, s, tx, ty) for d in ds)
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
                'viewBox="0 0 %d %d" fill="#000000" fill-rule="evenodd">\n'
                ' <title>%s</title>\n%s\n</svg>\n'
                % (canvas, canvas, canvas, canvas, title, body))

    files = {
        "fixture.svg":         doc(fx_f, "fixture"),
        "light.svg":           doc(lt_f, "light"),
        "symbol.svg":          doc(fx_f + lt_f, "moving head"),
        "head.svg":            doc(fx_f[:1], "head"),
        "yoke.svg":            doc(fx_f[1:], "yoke"),
        "fixture.outline.svg": doc(fx_o, "fixture, outline"),
        "head.outline.svg":    doc(fx_o[:1], "head, outline"),
        "yoke.outline.svg":    doc(fx_o[1:], "yoke, outline"),
        "light.outline.svg":   doc(lt_h, "light, outline"),
        "symbol.outline.svg":  doc(fx_o + lt_h, "moving head, outline"),
    }
    for name, data in files.items():
        open(os.path.join(outdir, name), "w").write(data)
    return sorted(files)


# ---- whole-symbol rotation ----------------------------------------------

def _rot_box(bb, deg):
    """Bounds of the design bbox after rotating it about its own centre (SVG space)."""
    X0, Y0, X1, Y1 = bb[0], -bb[3], bb[2], -bb[1]
    c = ((X0 + X1) / 2.0, (Y0 + Y1) / 2.0)
    a = math.radians(deg)
    co, si = math.cos(a), math.sin(a)
    pts = []
    for x, y in ((X0, Y0), (X1, Y0), (X1, Y1), (X0, Y1)):
        dx, dy = x - c[0], y - c[1]
        pts.append((c[0] + dx * co - dy * si, c[1] + dx * si + dy * co))
    xs = [q[0] for q in pts]; ys = [q[1] for q in pts]
    return (min(xs), min(ys), max(xs), max(ys)), c

def emit_rotated(outdir, deg, p=None, w_outline=4.6, w_fill=6.2):
    """Same file set as emit(), with the whole composition turned by deg."""
    os.makedirs(outdir, exist_ok=True)
    (fx_o, lt_o), bb_o, _ = build(w_outline, False, p)
    (fx_f, lt_f), bb_f, _ = build(w_fill, True, p)
    (_, lt_h), _, _ = build(w_outline, False, dict(p or {}, beam='hollow'))
    bb = (min(bb_o[0], bb_f[0]), min(bb_o[1], bb_f[1]),
          max(bb_o[2], bb_f[2]), max(bb_o[3], bb_f[3]))
    (X0, Y0, X1, Y1), c = _rot_box(bb, deg)
    box = ((X0 - PAD) * SCALE, (Y0 - PAD) * SCALE,
           (X1 - X0 + 2*PAD) * SCALE, (Y1 - Y0 + 2*PAD) * SCALE)
    spin = ' <g transform="rotate(%s %s %s)">\n%s\n </g>'

    def doc(ds, title):
        body = "\n".join(path(d) for d in ds)
        return svg(box, spin % (f(deg), f(c[0] * SCALE), f(c[1] * SCALE), body), title)

    files = {"fixture.svg": doc(fx_o, "fixture, outline"),
             "fixture.fill.svg": doc(fx_f, "fixture, filled"),
             "head.svg": doc(fx_f[:1], "head only"),
             "head.outline.svg": doc(fx_o[:1], "head only, outline"),
             "yoke.svg": doc(fx_f[1:], "yoke only"),
             "yoke.outline.svg": doc(fx_o[1:], "yoke only, outline"),
             "light.svg": doc(lt_f, "light"),
             "light.outline.svg": doc(lt_h, "light, outline"),
             "symbol.svg": doc(fx_o + lt_o, "moving head"),
             "symbol.outline.svg": doc(fx_o + lt_h, "moving head, outline"),
             "symbol.fill.svg": doc(fx_f + lt_f, "moving head, filled")}
    for name, data in files.items():
        open(os.path.join(outdir, name), "w").write(data)
    return box

def icon_layers_rotated(outdir, deg, p=None, canvas=1024.0, frac=0.62,
                        w_outline=4.6, w_fill=6.2):
    os.makedirs(outdir, exist_ok=True)
    (fx_o, lt_o), bb_o, _ = build(w_outline, False, p)
    (fx_f, lt_f), bb_f, _ = build(w_fill, True, p)
    (_, lt_h), _, _ = build(w_outline, False, dict(p or {}, beam='hollow'))
    bb = (min(bb_o[0], bb_f[0]), min(bb_o[1], bb_f[1]),
          max(bb_o[2], bb_f[2]), max(bb_o[3], bb_f[3]))
    (X0, Y0, X1, Y1), c = _rot_box(bb, deg)
    s = frac * canvas / max(X1 - X0, Y1 - Y0)
    tx = canvas / 2.0 - ((X0 + X1) / 2.0) * s
    ty = canvas / 2.0 - ((Y0 + Y1) / 2.0) * s

    def doc(ds, title):
        body = "\n".join('  <path d="%s"/>' % scale_path(d, s, tx, ty) for d in ds)
        spin = (' <g transform="rotate(%s %s %s)">\n%s\n </g>'
                % (f(deg), f(c[0] * s + tx), f(c[1] * s + ty), body))
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
                'viewBox="0 0 %d %d" fill="#000000" fill-rule="evenodd">\n'
                ' <title>%s</title>\n%s\n</svg>\n'
                % (canvas, canvas, canvas, canvas, title, spin))

    files = {"head.svg": doc(fx_f[:1], "head"), "yoke.svg": doc(fx_f[1:], "yoke"),
             "light.svg": doc(lt_f, "light"), "fixture.svg": doc(fx_f, "fixture"),
             "symbol.svg": doc(fx_f + lt_f, "moving head"),
             "head.outline.svg": doc(fx_o[:1], "head, outline"),
             "yoke.outline.svg": doc(fx_o[1:], "yoke, outline"),
             "light.outline.svg": doc(lt_h, "light, outline"),
             "symbol.outline.svg": doc(fx_o + lt_h, "moving head, outline")}
    for name, data in files.items():
        open(os.path.join(outdir, name), "w").write(data)
    return sorted(files)


# ---- head + light only, no yoke -----------------------------------------

def emit_pair(outdir, deg=0.0, p=None, w_outline=4.6, w_fill=6.2,
              canvas=1024.0, frac=0.70):
    """Head and light as separate layers on one shared canvas. No yoke anywhere,
    so the canvas is tight to those two parts only."""
    os.makedirs(outdir, exist_ok=True)
    (fx_o, lt_o), _, mo = build(w_outline, False, p)
    (fx_f, lt_f), _, mf = build(w_fill, True, p)
    (_, lt_h), _, _ = build(w_outline, False, dict(p or {}, beam='hollow'))

    def union(*bs):
        return (min(b[0] for b in bs), min(b[1] for b in bs),
                max(b[2] for b in bs), max(b[3] for b in bs))
    bb = union(mo['part']['head'], mo['part']['beam'],
               mf['part']['head'], mf['part']['beam'])
    (X0, Y0, X1, Y1), c = _rot_box(bb, deg)

    # 5x artwork, tight canvas
    box = ((X0 - PAD) * SCALE, (Y0 - PAD) * SCALE,
           (X1 - X0 + 2*PAD) * SCALE, (Y1 - Y0 + 2*PAD) * SCALE)
    def art(ds, title):
        body = "\n".join(path(d) for d in ds)
        g = (' <g transform="rotate(%s %s %s)">\n%s\n </g>'
             % (f(deg), f(c[0] * SCALE), f(c[1] * SCALE), body)) if deg else body
        return svg(box, g, title)

    # 1024 square, same placement for every layer
    s = frac * canvas / max(X1 - X0, Y1 - Y0)
    tx = canvas / 2.0 - ((X0 + X1) / 2.0) * s
    ty = canvas / 2.0 - ((Y0 + Y1) / 2.0) * s
    def sq(ds, title):
        body = "\n".join('  <path d="%s"/>' % scale_path(d, s, tx, ty) for d in ds)
        g = (' <g transform="rotate(%s %s %s)">\n%s\n </g>'
             % (f(deg), f(c[0] * s + tx), f(c[1] * s + ty), body)) if deg else body
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" '
                'viewBox="0 0 %d %d" fill="#000000" fill-rule="evenodd">\n'
                ' <title>%s</title>\n%s\n</svg>\n'
                % (canvas, canvas, canvas, canvas, title, g))

    sets = {"": (art, ""), "square-1024/": (sq, " (1024)")}
    for sub, (fn, suf) in sets.items():
        d = os.path.join(outdir, sub)
        os.makedirs(d, exist_ok=True)
        files = {"head.svg":          fn(fx_f[:1], "head" + suf),
                 "light.svg":         fn(lt_f, "light" + suf),
                 "head.outline.svg":  fn(fx_o[:1], "head, outline" + suf),
                 "light.outline.svg": fn(lt_h, "light, outline" + suf),
                 "both.svg":          fn(fx_f[:1] + lt_f, "head + light" + suf),
                 "both.outline.svg":  fn(fx_o[:1] + lt_h, "head + light, outline" + suf)}
        for name, data in files.items():
            open(os.path.join(d, name), "w").write(data)
    return box
