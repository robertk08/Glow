"""Parametric 'moving head' stage light drawn to SF Symbols geometry."""
import math
from geom import *

CAP = 70.459          # cap height of the SF Symbols small scale

P = dict(
    tilt      =  0.0,   # head tilt, degrees from straight down
    cone      = 21.5,   # beam half angle
    pivot_y   = 49.0,   # height of the tilt axis
    back_t    = -10.5,  # head extent behind the pivot
    lens_t    =  10.5,  # head extent in front of the pivot
    back_half =  8.0,   # head half width at the back
    lens_half = 12.4,   # head half width at the lens
    yoke_gap  =  3.6,   # clearance between yoke arm and head
    yoke_r    =  8.0,   # outer corner radius of the yoke bracket
    arm_bot   = 44.0,   # where the yoke arms end
    beam_gap  =  3.2,   # gap between lens and start of beam
    floor     =  0.0,   # where the beam lands
    r_back    =  5.2,   # corner radius at the back of the head
    r_lens    =  2.6,   # corner radius at the lens
    beam      = 'solid',    # solid | hollow | closed | open | rays
)

def yoke(ax, w, r_out, arm_bot):
    """Inverted-U bracket: two arms joined by the mounting bar on top."""
    h = w / 2.0
    ri = max(r_out - w, 0.8)
    pts = [(-ax - h, arm_bot), (-ax - h, CAP), (ax + h, CAP), (ax + h, arm_bot),
           (ax - h, arm_bot), (ax - h, CAP - w), (-ax + h, CAP - w), (-ax + h, arm_bot)]
    radii = [h, r_out, r_out, h, h, ri, ri, h]
    return rounded_polygon(pts, radii), poly_bbox(pts)

def build(w, fill=False, p=None):
    """Return (layers, bbox); layers = [fixture, beam] lists of path data."""
    p = dict(P, **(p or {}))
    d = polar(p['tilt'])            # beam axis (down-forward)
    n = perp(d)                     # head's right-hand side
    k = w - 4.6                     # weight delta from Regular
    back_half = p['back_half'] + k * 0.45
    lens_half = p['lens_half'] + k * 0.45
    pivot = (0.0, p['pivot_y'])
    h = w / 2.0

    fixture, beam, boxes = [], [], []

    # ---- head ---------------------------------------------------------
    back_c = add(pivot, mul(d, p['back_t']))
    lens_c = add(pivot, mul(d, p['lens_t']))
    head = [add(back_c, mul(n, -back_half)), add(back_c, mul(n, back_half)),
            add(lens_c, mul(n,  lens_half)), add(lens_c, mul(n, -lens_half))]
    rb, rl = p['r_back'] + k * 0.2, p['r_lens'] + k * 0.2
    r_head = [rb, rb, rl, rl]
    if fill:
        fixture.append(rounded_polygon(head, r_head)); boxes.append(poly_bbox(head))
    else:
        dp, bb = hollow_polygon(head, r_head, w)
        fixture.append(dp); boxes.append(bb)

    # ---- yoke ---------------------------------------------------------
    ax = max(abs(c[0]) for c in head) + p['yoke_gap'] + h
    dp, bb = yoke(ax, w, p['yoke_r'] + k * 0.3, p['arm_bot'])
    fixture.append(dp); boxes.append(bb)

    # ---- beam ---------------------------------------------------------
    mouth = add(lens_c, mul(d, p['beam_gap'] + h))
    sL = add(mouth, mul(n, -lens_half))
    sR = add(mouth, mul(n,  lens_half))
    dL, dR = polar(p['tilt'] - p['cone']), polar(p['tilt'] + p['cone'])
    span = (sL[1] - p['floor'] - h) / abs(dL[1])
    eL, eR = add(sL, mul(dL, span)), add(sR, mul(dR, span))
    meta = dict(mouth=mouth, lens=lens_c, sL=sL, sR=sR, dL=dL, dR=dR, span=span, w=w)
    style = 'solid' if fill else p['beam']
    wedge = [sL, eL, eR, sR]
    meta['wedge'] = wedge
    if style == 'solid':
        beam.append(rounded_polygon(wedge, h * 1.1)); boxes.append(poly_bbox(wedge))
    elif style == 'hollow':
        dp, bb = hollow_polygon(wedge, h * 1.1, w)
        beam.append(dp); boxes.append(bb)
    else:
        segs = [(sL, eL), (sR, eR)]
        if style == 'closed':
            segs.insert(1, (eL, eR))
        if style == 'rays':
            c0 = add(mouth, mul(d, 0.0))
            segs.append((c0, add(c0, mul(d, span * 0.62))))
        for a, b in segs:
            seg, bb = capsule(a, b, w)
            beam.append(seg); boxes.append(bb)

    bbox = (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))
    return [fixture, beam], bbox, meta
