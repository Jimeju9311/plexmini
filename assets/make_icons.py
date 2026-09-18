#!/usr/bin/env python3
"""Generates the PlexMini app icon at every size iOS 9/10 asks for.

The mark is three rising bars in the app's amber accent on charcoal: a play
button would have been the obvious choice, but it reads as a generic media
control, and anything resembling Plex's own chevron was off the table since
this project is unaffiliated with Plex Inc.

The artwork is drawn here from plain geometry rather than traced from an icon
set, so it is original work and carries the same MIT licence as the rest of the
repo. Regenerate with:

    python3 assets/make_icons.py            # needs Pillow

Generated PNGs are committed, so building the app does not require Python.
"""
from PIL import Image, ImageDraw
import os

SS = 8  # supersample factor; downscaled with LANCZOS for clean edges
CHARCOAL = (24, 26, 30)
AMBER = (230, 166, 33)
AMBER_MID = (196, 140, 26)
AMBER_DIM = (146, 104, 20)

# iOS 9/10 picks from CFBundleIconFiles by size. iPad 4 is retina, so 152 is the
# one that actually shows on its home screen; the rest cover Spotlight,
# Settings and older devices. Keep this list in sync with CFBundleIconFiles in
# Info.plist - build.sh copies every icon here into the bundle.
SIZES = [29, 40, 50, 57, 58, 72, 76, 80, 87, 100, 114, 120, 144, 152, 167, 180]


def render(px):
    """Three rounded bars of increasing height, centred as a group."""
    s = px * SS
    img = Image.new("RGB", (s, s), CHARCOAL)
    d = ImageDraw.Draw(img)

    bar_w = s * 0.118
    gap = s * 0.062
    x = (s - (bar_w * 3 + gap * 2)) / 2
    heights = [0.20, 0.31, 0.42]
    # Centre the group on the tallest bar so the cluster sits optically centred
    # rather than hanging from a shared baseline.
    base = s / 2 + s * max(heights) / 2

    for h, color in zip(heights, (AMBER_DIM, AMBER_MID, AMBER)):
        d.rounded_rectangle([x, base - s * h, x + bar_w, base],
                            radius=bar_w / 2, fill=color)
        x += bar_w + gap

    return img.resize((px, px), Image.LANCZOS)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    icon_dir = os.path.join(here, "icons")
    os.makedirs(icon_dir, exist_ok=True)

    for px in SIZES:
        # No alpha channel: iOS expects opaque icons and applies its own mask
        # and corner radius, so a transparent background renders as black.
        render(px).convert("RGB").save(os.path.join(icon_dir, "Icon-%d.png" % px))
    print("wrote %d icons to %s" % (len(SIZES), icon_dir))

    render(512).save(os.path.join(here, "logo.png"))
    print("wrote logo.png")


if __name__ == "__main__":
    main()
