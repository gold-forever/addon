"""Writes the web skin's two textures as 64x64 uncompressed 32-bit TGA: a white anti-aliased circle (sliced
into nine for rounded corners of any radius) and a soft shadow (a rectangle's blurred edge)."""
import math, struct, sys

def tga(path, size, alpha):
    head = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8 | 0x20)  # top-left origin
    body = bytearray()
    for y in range(size):
        for x in range(size):
            a = max(0, min(255, round(alpha(x + 0.5, y + 0.5) * 255)))
            body += bytes((255, 255, 255, a))  # white: the kit tints with SetVertexColor
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

out = sys.argv[1]
tga(f'{out}/Round.tga', S, circle)
tga(f'{out}/Shadow.tga', S, shadow)
