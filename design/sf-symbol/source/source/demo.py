import re, os

def load(d, name, uid):
    s = open(os.path.join("artwork-5x", d, name)).read()
    s = re.sub(r'\bid="([^"]+)"', lambda m: 'id="%s-%s"' % (m.group(1), uid), s)
    s = s.replace('<svg ', '<svg class="art" ', 1)
    return re.sub(r'\swidth="[^"]*"\sheight="[^"]*"', '', s, count=1)

def fig(label, inner, cls=""):
    return '<figure class="%s">%s<figcaption>%s</figcaption></figure>' % (cls, inner, label)

parts = []
for d in ("straight", "tilt"):
    cells = "".join(fig(n.replace(".svg", ""), load(d, n, d))
                    for n in ("fixture.svg", "light.svg", "light.outline.svg",
                              "light.bands.svg", "symbol.fill.svg"))
    over = ('<div class="stack">%s%s</div>'
            % (load(d, "fixture.fill.svg", d + "o1").replace('class="art"', 'class="art a"'),
               load(d, "light.svg", d + "o2").replace('class="art"', 'class="art b"')))
    anim = ('<div class="anim">%s</div>' % load(d, "layered.svg", d + "an"))
    bands = ('<div class="bandanim">%s</div>'
             % load(d, "light.bands.svg", d + "bn"))
    parts.append('<h2>%s</h2><div class="row">%s%s%s%s</div>'
                 % (d, cells, fig("overlay check", over),
                    fig("light scales out from the apex", anim),
                    fig("bands travel outward", bands)))

CSS = """
:root{color-scheme:light dark}
body{font:14px/1.5 -apple-system,BlinkMacSystemFont,sans-serif;margin:0;padding:30px 26px 70px;
     background:#fff;color:#1c1c1e}
h1{font-size:21px;margin:0 0 4px}
p.sub{color:#8a8a8e;margin:0 0 24px;max-width:62ch}
h2{font-size:11px;text-transform:uppercase;letter-spacing:.09em;color:#8a8a8e;
   margin:32px 0 12px;border-top:1px solid #e6e6e8;padding-top:12px}
.row{display:flex;gap:26px;align-items:flex-end;flex-wrap:wrap}
figure{margin:0;text-align:center}
figcaption{font-size:10px;color:#9a9a9e;margin-top:8px;max-width:150px}
svg.art{height:150px;width:auto;display:block}
.stack{position:relative;height:150px}
.stack svg.art{position:absolute;inset:0}
.stack svg.a{color:#1c1c1e;opacity:.25}
.stack svg.b{color:#ff3b30;opacity:.8}
.anim [id^=light] {animation:out 2.2s cubic-bezier(.3,.7,.4,1) infinite}
@keyframes out{0%{transform:scale(.2);opacity:0}
               25%{opacity:.85}
               70%{transform:scale(1);opacity:.7}
               100%{transform:scale(1.03);opacity:0}}
.bandanim [id^=band]{animation:trav 1.5s ease-in-out infinite}
.bandanim [id^=band-2]{animation-delay:.16s}
.bandanim [id^=band-3]{animation-delay:.32s}
@keyframes trav{0%,100%{opacity:.18}45%{opacity:1}}
@media (prefers-color-scheme:dark){body{background:#000;color:#f2f2f7}
 h2{border-color:#2c2c2e}.stack svg.a{color:#f2f2f7}}
"""
html = ('<!doctype html><meta charset="utf-8"><title>movinghead layers</title>'
        '<style>%s</style>\n<h1>movinghead — separated layers</h1>'
        '<p class="sub">Every file in a folder shares one viewBox, so the pieces drop on top of '
        'each other with no positioning. The light is anchored at the cone apex, so a plain '
        'scale animates it outward along the beam.</p>%s' % (CSS, "".join(parts)))
open("layers.html", "w").write(html)
print("ok")
