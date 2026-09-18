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

# Launch images, keyed by the filename iOS looks for -> native pixel size.
# The iPad 4 is retina, so the @2x~ipad pair is what it actually uses; the rest
# keep the iPhone/non-retina cases from falling back to a scaled-up icon.
LAUNCH_IMAGES = {
    "LaunchImage-iPad-Portrait~ipad.png": (768, 1024),
    "LaunchImage-iPad-Portrait@2x~ipad.png": (1536, 2048),
    "LaunchImage-iPad-Landscape~ipad.png": (1024, 768),
    "LaunchImage-iPad-Landscape@2x~ipad.png": (2048, 1536),
    "LaunchImage-iPhone@2x.png": (640, 960),
    "LaunchImage-iPhone-568h@2x.png": (640, 1136),
}


def draw_mark(draw, cx, cy, unit):
    """Three rounded bars of increasing height, centred on (cx, cy).

    Every dimension is a fraction of `unit`, so the same mark can be drawn onto a
    square icon or a full-screen launch image at any aspect ratio.
    """
    bar_w = unit * 0.118
    gap = unit * 0.062
    heights = [0.20, 0.31, 0.42]

    x = cx - (bar_w * 3 + gap * 2) / 2
    # Centre the group on the tallest bar so the cluster sits optically centred
    # rather than hanging from a shared baseline.
    base = cy + unit * max(heights) / 2

    for h, color in zip(heights, (AMBER_DIM, AMBER_MID, AMBER)):
        draw.rounded_rectangle([x, base - unit * h, x + bar_w, base],
                               radius=bar_w / 2, fill=color)
        x += bar_w + gap


def render(px):
    """The square app icon."""
    s = px * SS
    img = Image.new("RGB", (s, s), CHARCOAL)
    draw_mark(ImageDraw.Draw(img), s / 2, s / 2, s)
    return img.resize((px, px), Image.LANCZOS)


def render_launch(w, h):
    """The launch image, drawn at the device's native pixel size.

    Without one, iOS scales the largest app icon (180px) up to fill the screen
    during the open animation, which on a 2048x1536 panel looks obviously soft.
    The mark is sized off the short edge so it stays identical between portrait
    and landscape.
    """
    ss = 4  # lower than the icons' 8x: these canvases are already huge
    W, H = w * ss, h * ss
    img = Image.new("RGB", (W, H), CHARCOAL)
    # Sized so the mark reads as the same logo the user just tapped, rather than a
    # small dot adrift in a large field.
    draw_mark(ImageDraw.Draw(img), W / 2, H / 2, min(W, H) * 0.62)
    return img.resize((w, h), Image.LANCZOS)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    icon_dir = os.path.join(here, "icons")
    os.makedirs(icon_dir, exist_ok=True)

    for px in SIZES:
        # No alpha channel: iOS expects opaque icons and applies its own mask
        # and corner radius, so a transparent background renders as black.
        render(px).convert("RGB").save(os.path.join(icon_dir, "Icon-%d.png" % px))
    print("wrote %d icons to %s" % (len(SIZES), icon_dir))

    # Launch images. The filename suffixes are what iOS matches against, and the
    # sizes in Info.plist's UILaunchImages are in *points*, so a retina iPad asks
    # for {768, 1024} and is served the @2x~ipad file at 1536x2048 pixels.
    for name, (w, h) in LAUNCH_IMAGES.items():
        render_launch(w, h).convert("RGB").save(os.path.join(icon_dir, name))
    print("wrote %d launch images" % len(LAUNCH_IMAGES))

    render(512).save(os.path.join(here, "logo.png"))
    print("wrote logo.png")


if __name__ == "__main__":
    main()
