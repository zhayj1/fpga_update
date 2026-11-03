"""Precompress keyed circular cover art for a 4:3 to 16:10 display stretch."""
from PIL import Image, ImageDraw

KEY = (255, 0, 255)


def correct_circle(image: Image.Image) -> Image.Image:
    if image.size != (240, 240):
        raise ValueError("cover must be 240x240")
    image = image.convert("RGB")
    alpha = Image.new("L", image.size)
    alpha.putdata([0 if pixel == KEY else 255 for pixel in image.getdata()])
    rgba = image.copy()
    rgba.putalpha(alpha)
    narrow = rgba.resize((200, 240), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (240, 240), KEY)
    circle = Image.new("L", (240, 240), 0)
    ImageDraw.Draw(circle).ellipse((20, 0, 219, 239), fill=255)
    narrow_alpha = Image.new("L", (240, 240), 0)
    narrow_alpha.paste(narrow.getchannel("A"), (20, 0))
    # Keep a binary key: the hardware has no partial-transparency pixels.
    circle.putdata([255 if c and a >= 128 else 0
                    for c, a in zip(circle.getdata(), narrow_alpha.getdata())])
    canvas.paste(narrow.convert("RGB"), (20, 0))
    canvas.paste(Image.new("RGB", canvas.size, KEY), (0, 0),
                 Image.eval(circle, lambda value: 255 - value))
    return canvas
