# straight

All files share one viewBox, so they stack with no positioning:

    viewBox="-128.914 -358.295 257.828 352.795"   (257.828 x 352.795 px at 5x)

Light animation origin (cone apex), measured from the top-left of the
viewBox - use it as transform-origin with transform-box: view-box:

    128.914 px  30.76 px

- fixture.svg / fixture.fill.svg - yoke + head
- head.svg / yoke.svg (+ .outline) - the two split apart
- light.svg / light.outline.svg / light.bands.svg - the beam only
- symbol.svg, symbol.outline.svg, symbol.fill.svg - assembled
- layered.svg - both, as #fixture and #light, origin already set
