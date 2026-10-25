"""Writes the addon's own textures as 64x64 uncompressed 32-bit TGA: a white anti-aliased circle (sliced
into nine for rounded corners of any radius), a soft shadow (a rectangle's blurred edge), and the icon
(a gold coin) for the minimap button and the addon compartment."""
import math, struct, sys

def tga(path, size, alpha, rgb=lambda x, y: (255, 255, 255)):
    head = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8 | 0x20)  # top-left origin
    body = bytearray()
    for y in range(size):
        for x in range(size):
            a = max(0, min(255, round(alpha(x + 0.5, y + 0.5) * 255)))
            r, g, b = rgb(x + 0.5, y + 0.5)
            body += bytes((b, g, r, a))  # white unless coloured: the kit tints with SetVertexColor
    open(path, 'wb').write(head + body)

S = 64
def circle(x, y):
    d = math.hypot(x - S / 2, y - S / 2)
    return max(0.0, min(1.0, S / 2 - d + 0.5))  # one pixel of anti-aliasing

CORE_LO, CORE_HI, BLUR = 24, 40, 24
def shadow(x, y):
    dx = max(CORE_LO - x, 0, x - CORE_HI)
    dy = max(CORE_LO - y, 0, y - CORE_HI)
    d = math.hypot(dx, dy) / BLUR
    return max(0.0, math.exp(-4.5 * d * d) - math.exp(-4.5)) / (1 - math.exp(-4.5))

# The icon: a gold coin, lit from the top left, with a darker rim and an inner ring. Our own drawing.
def coin_rgb(x, y):
    d = math.hypot(x - S / 2, y - S / 2) / (S / 2)
    light = 1 - 0.35 * ((x + y) / S)  # brighter towards the top left
    base = (242, 201, 76) if d < 0.78 else (196, 146, 40)  # face, then rim
    if 0.62 < d < 0.68:
        base = (176, 128, 34)  # the ring stamped in the face
    return tuple(max(0, min(255, round(c * light))) for c in base)

# The arcane look's light: a soft round glow (inner light, a button's pulse), a rune point (a bright core
# in a thin ring) and a spark (a soft horizontal streak: the light along the title rule, a bar's end).
def glow(x, y):
    d = math.hypot(x - S / 2, y - S / 2) / (S / 2)
    return max(0.0, 1 - d) ** 2

def rune(x, y):
    d = math.hypot(x - S / 2, y - S / 2) / (S / 2)
    core = max(0.0, 1 - d / 0.28) ** 1.5
    ring = max(0.0, 1 - abs(d - 0.62) / 0.06) * 0.8
    halo = max(0.0, 1 - d) ** 3 * 0.5
    return min(1.0, core + ring + halo)

def spark(x, y):
    dx = abs(x - S / 2) / (S / 2)
    dy = abs(y - S / 2) / (S / 2)
    return max(0.0, 1 - dx) ** 1.6 * max(0.0, 1 - dy) ** 2

out = sys.argv[1]
tga(f'{out}/Round.tga', S, circle)
tga(f'{out}/Shadow.tga', S, shadow)
tga(f'{out}/Icon.tga', S, circle, coin_rgb)
tga(f'{out}/Glow.tga', S, glow)
tga(f'{out}/Rune.tga', S, rune)
tga(f'{out}/Spark.tga', S, spark)
