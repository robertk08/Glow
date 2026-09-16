# tilt45

All files share one viewBox, so they stack with no positioning:

    viewBox="-138.509 -358.295 378.009 352.795"   (378.009 x 352.795 px at 5x)

Light animation origin (cone apex), measured from the top-left of the
viewBox - use it as transform-origin with transform-box: view-box:

    55.144 px  29.93 px

- fixture.svg / fixture.fill.svg - yoke + head
- head.svg / yoke.svg (+ .outline) - the two split apart
- light.svg / light.outline.svg / light.bands.svg - the beam only
- symbol.svg, symbol.outline.svg, symbol.fill.svg - assembled
- layered.svg - both, as #fixture and #light, origin already set
