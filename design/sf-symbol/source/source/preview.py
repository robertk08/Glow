from movinghead import build, CAP

def standalone(w, fill=False, color="currentColor", pad=2.0, p=None):
    layers, bb, _ = build(w, fill, p)
    x0, y0, x1, y1 = bb
    vb = "%.2f %.2f %.2f %.2f" % (x0 - pad, -y1 - pad, (x1 - x0) + 2*pad, (y1 - y0) + 2*pad)
    body = "".join('<path fill="%s" d="%s"/>' % (color, d) for L in layers for d in L)
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s">%s</svg>' % (vb, body)

CSS = """body{font:13px -apple-system,sans-serif;background:#fff;color:#111;margin:24px}
h2{font-size:12px;text-transform:uppercase;letter-spacing:.08em;color:#888;margin:28px 0 8px}
.row{display:flex;gap:34px;align-items:flex-end;flex-wrap:wrap}
.c{text-align:center}.sym{display:flex;align-items:flex-end;justify-content:center}
.sym svg{height:100%;width:auto}
.l{font-size:10px;color:#999;margin-top:6px}
.sq{width:190px;height:190px;border-radius:44px;display:inline-flex;align-items:center;
    justify-content:center;margin-right:22px;
    background:linear-gradient(160deg,#5b2bd9,#c2178b 55%,#ff7a2f)}
.sq svg{height:58%;width:auto}"""

def cell(label, w, fill, px, p=None):
    return ('<div class="c"><div class="sym" style="height:%dpx">%s</div>'
            '<div class="l">%s</div></div>') % (px, standalone(w, fill, p=p), label)

def main():
    out = ['<div class="row" style="gap:0">']
    for fill in (True, False):
        out.append('<div class="sq">%s</div>' % standalone(6.2 if fill else 5.4, fill, "#fff"))
    out.append('</div>')
    for fill in (False, True):
        out.append('<h2>%s</h2><div class="row">' % ("fill" if fill else "outline"))
        for lbl, w in (("Ultralight", 2.8), ("Regular", 4.6), ("Black", 7.1)):
            out.append(cell(lbl, w, fill, 150))
        out.append('</div><div class="row" style="margin-top:16px">')
        for px in (72, 44, 30, 22, 17):
            out.append(cell("%dpx" % px, 4.6, fill, px))
        out.append('</div>')
    open("preview.html", "w").write(
        '<!doctype html><meta charset="utf-8"><style>%s</style>%s' % (CSS, "".join(out)))
    print("written preview.html")

if __name__ == "__main__":
    main()
