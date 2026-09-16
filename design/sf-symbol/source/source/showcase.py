from preview import standalone

TILT = dict(tilt=15.0, cone=20.0)
S = lambda w, f=False, p=None, c="currentColor": standalone(w, f, c, p=p)

def box(label, inner):
    return '<figure>%s<figcaption>%s</figcaption></figure>' % (inner, label)

def sym(h, w, f=False, p=None, c="currentColor"):
    return '<div class="s" style="height:%spx">%s</div>' % (h, S(w, f, p, c))

fam = "".join(box(n, sym(120, 4.6, f, p)) for n, f, p in
              (("movinghead", False, None), ("movinghead.fill", True, None),
               ("movinghead.tilt", False, TILT), ("movinghead.tilt.fill", True, TILT)))
weights = "".join(box(n, sym(110, w)) for n, w in
                  (("Ultralight", 2.8), ("Light", 3.5), ("Regular", 4.6),
                   ("Semibold", 5.6), ("Bold", 6.3), ("Black", 7.1)))
small = "".join(box("%dpt" % px, sym(px, 4.6)) + box("%dpt" % px, sym(px, 4.6, True))
                for px in (44, 30, 22, 17, 13))
GRADS = [("linear-gradient(160deg,#2b1a5e,#5b2bd9 45%,#c2178b)", 6.2, True, None),
         ("linear-gradient(160deg,#111,#2b2b33)", 6.2, True, None),
         ("linear-gradient(160deg,#ff9d00,#ff2d55 60%,#8a2be2)", 6.2, True, TILT),
         ("linear-gradient(160deg,#0a84ff,#30d0c6)", 5.4, False, None)]
icons = "".join('<div class="sq" style="background:%s">%s</div>' % (g, S(w, f, p, "#fff"))
                for g, w, f, p in GRADS)

TPL = """<!doctype html><meta charset="utf-8"><title>movinghead</title><style>
:root{color-scheme:light dark}
body{font:14px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:32px 28px 64px;
     background:#fff;color:#1c1c1e;max-width:1000px}
h1{font-size:22px;margin:0 0 4px}
p.sub{color:#8a8a8e;margin:0 0 30px}
h2{font-size:11px;text-transform:uppercase;letter-spacing:.09em;color:#8a8a8e;
   margin:34px 0 12px;border-top:1px solid #e6e6e8;padding-top:12px}
.row{display:flex;gap:30px;align-items:flex-end;flex-wrap:wrap}
figure{margin:0;text-align:center}
figcaption{font-size:10px;color:#9a9a9e;margin-top:8px}
.s{display:flex;align-items:flex-end;justify-content:center}
.s svg{height:100%;width:auto}
.sq{width:150px;height:150px;border-radius:34px;display:flex;align-items:center;
    justify-content:center}
.sq svg{height:56%;width:auto}
@media (prefers-color-scheme:dark){body{background:#000;color:#f2f2f7}
 h2{border-color:#2c2c2e}}
</style>
<h1>movinghead</h1>
<p class="sub">Custom SF Symbol — yoke, head and beam. Two layers: fixture (primary) and beam (secondary).</p>
<h2>Family</h2><div class="row">{fam}</div>
<h2>Weights</h2><div class="row">{weights}</div>
<h2>At size</h2><div class="row">{small}</div>
<h2>On an app icon</h2><div class="row">{icons}</div>
"""
html = TPL.replace("{fam}",fam).replace("{weights}",weights).replace("{small}",small).replace("{icons}",icons)
open("showcase.html", "w").write(html)
print("ok")
