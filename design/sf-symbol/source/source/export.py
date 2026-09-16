"""Write SF Symbols custom-symbol templates (Ultralight/Regular/Black, small scale)."""
import re
from movinghead import build, CAP

SRC = "/Applications/SF Symbols.app/Contents/Resources/badge.plus.svg"
BASELINE = 696.0
WEIGHTS = [("Ultralight", 2.8, 559.711), ("Regular", 4.6, 1449.84), ("Black", 7.1, 2933.4)]

STYLE = """ <style>.monochrome-0 {fill:#000000}
.monochrome-1 {fill:#000000}

.multicolor-0:tintColor {fill:#000000}
.multicolor-1:systemYellowColor {fill:#FFCC00}

.hierarchical-0:primary {fill:#000000}
.hierarchical-1:secondary {fill:#000000}
</style>
"""
CLASSES = ["monochrome-0 multicolor-0:tintColor hierarchical-0:primary",
           "monochrome-1 multicolor-1:systemYellowColor hierarchical-1:secondary"]

def _chrome():
    """Notes + Guides straight from an Apple-generated template."""
    src = open(SRC).read()
    notes = src[src.index(' <g id="Notes">'):src.index(' <g id="Guides">')]
    guides = src[src.index(' <g id="Guides">'):src.index(' <g id="Symbols">')]
    guides = guides[:guides.index('  <line id="left-margin-')] 
    return notes, guides

NOTES, GUIDES_HEAD = _chrome()

def template(fill=False, p=None):
    margins, groups = [], []
    for name, w, center in WEIGHTS:
        layers, bb, _ = build(w, fill, p)
        width = bb[2] - bb[0]
        left, right = center - width / 2.0, center + width / 2.0
        for side, x in (("left", left), ("right", right)):
            margins.append('  <line id="%s-margin-%s-S" style="fill:none;stroke:#00AEEF;'
                           'stroke-width:0.5;opacity:1.0;" x1="%.3f" x2="%.3f" y1="600.785" '
                           'y2="720.121"/>\n' % (side, name, x, x))
        paths = []
        for i, layer in enumerate(layers):
            for d in layer:
                paths.append('   <path class="%s" d="%s"/>\n' % (CLASSES[i], d))
        groups.append('  <g id="%s-S" transform="matrix(1 0 0 1 %.3f %.0f)">\n%s  </g>\n'
                      % (name, left - bb[0], BASELINE, "".join(paths)))
    groups.reverse()
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" '
            '"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n'
            '<svg version="1.1" xmlns="http://www.w3.org/2000/svg" '
            'xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">\n'
            ' <!--glyph: "", point size: 100.0, template writer version: "101"-->\n'
            + STYLE + NOTES + GUIDES_HEAD + "".join(margins) + " </g>\n"
            + ' <g id="Symbols">\n' + "".join(groups) + ' </g>\n</svg>\n')

def plain(w, fill=False, p=None, pad=1.0):
    """Flat SVG of a single weight, for artwork / icon use."""
    layers, bb, _ = build(w, fill, p)
    x0, y0, x1, y1 = bb
    body = "".join('<path d="%s"/>' % d for L in layers for d in L)
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%.2f %.2f %.2f %.2f" fill="#000">'
            '%s</svg>\n' % (x0 - pad, -y1 - pad, (x1 - x0) + 2*pad, (y1 - y0) + 2*pad, body))

if __name__ == "__main__":
    import os
    os.makedirs("out", exist_ok=True)
    TILT = dict(tilt=15.0, cone=20.0)
    jobs = [("movinghead", False, None), ("movinghead.fill", True, None),
            ("movinghead.tilt", False, TILT), ("movinghead.tilt.fill", True, TILT)]
    for name, fill, p in jobs:
        open("out/%s.svg" % name, "w").write(template(fill, p))
        open("out/%s.plain.svg" % name, "w").write(plain(4.6, fill, p))
    open("out/movinghead.icon.svg", "w").write(plain(6.2, True))
    for f in sorted(os.listdir("out")):
        print(f, os.path.getsize("out/" + f))
