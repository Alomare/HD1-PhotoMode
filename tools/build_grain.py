"""Builds Photo Mode's film grain: one texture of four tiles of Gaussian noise and its material, for the
Grain row of the Film tab.

Usage: python tools/build_grain.py

Each tile is 512 by 512 and wraps at its edges, so tiles laid side by side show no seams. The first two
come from one field of noise: "light" holds where it's above the middle and "dark" where it's below, so
drawn one in white and the other in black they lighten and darken the picture by the same amounts. The
other two are fields of their own, for the green and blue of color grain (the first tile gives the red).
The noise is softened by a blur of under a pixel, as film grain is, and every build is the same.

The texture is white with the noise in its alpha, and the material is the game's font material, whose
shader multiplies the texture's alpha by the color it's drawn with: the same recipe as Helldivers
Arcade's art, which the game has drawn since 2026-11-01. Writes res/grain.texture, res/grain.material
and internal/grain_preview.png. Needs numpy and Pillow.
"""
import struct
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES, INTERNAL = ROOT / "res", ROOT / "internal"

TILE = 512
RESOURCE_BASE = "photomode/grain"
MATERIAL_NAME = "photomode_grain"
MATERIAL_VERSION = 10
# The game's font material: the shader multiplies a white texture's alpha by the vertex color.
TEMPLATE, DIFFUSE_MAP, VARIABLE = 0xba25de35, 0x3aa8b87e, 0x46f80ade
SPREAD = 2.6   # standard deviations that reach full alpha
SOFTEN = 0.6   # the blur's sigma, in pixels


def murmur64(data, seed=0):
    m, r, mask = 0xc6a4a7935bd1e995, 47, (1 << 64) - 1
    h = (seed ^ (len(data) * m)) & mask
    tail = len(data) & ~7
    for (k,) in struct.iter_unpack("<Q", data[:tail]):
        k = (k * m) & mask
        k ^= k >> r
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    rest = data[tail:]
    if rest:
        h = ((h ^ int.from_bytes(rest, "little")) * m) & mask
    h ^= h >> r
    h = (h * m) & mask
    return h ^ (h >> r)


def field(rng):
    """Gaussian noise of mean 0 and deviation 1 that wraps at its edges, softened by a small blur."""
    n = rng.standard_normal((TILE, TILE)).astype(np.float32)
    # A blur in the frequency domain wraps at the edges by itself.
    fy = np.fft.fftfreq(TILE)[:, None]
    fx = np.fft.fftfreq(TILE)[None, :]
    gauss = np.exp(-2 * (np.pi * SOFTEN) ** 2 * (fx * fx + fy * fy))
    soft = np.real(np.fft.ifft2(np.fft.fft2(n) * gauss)).astype(np.float32)
    return soft / soft.std()


def alpha(values):
    return Image.fromarray((np.clip(values / SPREAD, 0, 1) * 255 + 0.5).astype(np.uint8), "L")


def tiles():
    rng = np.random.default_rng(1609)
    first, second, third = field(rng), field(rng), field(rng)
    return {"light": alpha(first), "dark": alpha(-first), "green": alpha(second), "blue": alpha(third)}


PLACES = {"light": (0, 0), "dark": (TILE, 0), "green": (0, TILE), "blue": (TILE, TILE)}


def atlas(parts):
    out = Image.new("L", (TILE * 2, TILE * 2), 0)
    for name, image in parts.items():
        out.paste(image, PLACES[name])
    return out


def alpha_blocks(image):
    width, height = image.size
    pad_w, pad_h = (4 - width % 4) % 4, (4 - height % 4) % 4
    a = np.pad(np.asarray(image, dtype=np.int32), ((0, pad_h), (0, pad_w)), mode="edge")
    blocks = a.reshape(a.shape[0] // 4, 4, a.shape[1] // 4, 4).transpose(0, 2, 1, 3).reshape(-1, 16)
    high, low = blocks.max(axis=1), blocks.min(axis=1)
    steps = np.arange(1, 7)
    ramp = np.zeros((len(blocks), 8), dtype=np.int32)
    ramp[:, 0], ramp[:, 1] = high, low
    ramp[:, 2:] = ((7 - steps)[None, :] * high[:, None] + steps[None, :] * low[:, None]) // 7
    best = np.abs(blocks[:, :, None] - ramp[:, None, :]).argmin(axis=2).astype(np.uint64)
    best[high == low] = 0
    bits = np.zeros(len(blocks), dtype=np.uint64)
    for i in range(16):
        bits |= best[:, i] << np.uint64(3 * i)
    out = bytearray(len(blocks) * 16)
    colour = b"\xff\xff\xff\xff\0\0\0\0"
    for i, (h, l, b) in enumerate(zip(high.tolist(), low.tolist(), bits.tolist())):
        out[i * 16:i * 16 + 16] = bytes((h, l)) + b.to_bytes(6, "little") + colour
    return bytes(out)


def dds(image):
    """DXT5 with every mip, in the layout of the game's own atlases."""
    width, height = image.size
    mips = [image]
    while mips[-1].size != (1, 1):
        w, h = mips[-1].size
        mips.append(mips[-1].resize((max(1, w // 2), max(1, h // 2)), Image.Resampling.BOX))
    header = bytearray(128)
    header[:4] = b"DDS "
    struct.pack_into("<IIIIIII", header, 4, 124, 0x000a1007, height, width, width * height, 0, len(mips))
    header[60:64], header[68:72] = b"UVER", b"NVTT"
    struct.pack_into("<I", header, 72, 0x00020100)
    struct.pack_into("<II4s", header, 76, 32, 4, b"DXT5")
    struct.pack_into("<I", header, 108, 0x00401008)
    # Every texture resource ends with a four byte category, or the game stalls at boot.
    return bytes(header) + b"".join(alpha_blocks(m) for m in mips) + bytes(4)


def material():
    name = murmur64(MATERIAL_NAME.encode()) >> 32
    tex = murmur64(f"{RESOURCE_BASE}/atlas".encode())
    record = struct.pack("<13I", name, TEMPLATE, 0, 0, 1, DIFFUSE_MAP, tex & 0xffffffff, tex >> 32, 1, VARIABLE, 0, 0, 0)
    return struct.pack("<II", MATERIAL_VERSION, 1) + record


def preview(parts):
    """The mono grain as it would look over a mid grey, at full strength."""
    grey = np.full((TILE, TILE), 128.0)
    light = np.asarray(parts["light"], dtype=np.float32) / 255
    dark = np.asarray(parts["dark"], dtype=np.float32) / 255
    out = grey + (255 - grey) * light * 0.5 - grey * dark * 0.5
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "L")


def main():
    parts = tiles()
    RES.mkdir(exist_ok=True)
    INTERNAL.mkdir(exist_ok=True)
    (RES / "grain.texture").write_bytes(dds(atlas(parts)))
    (RES / "grain.material").write_bytes(material())
    preview(parts).save(INTERNAL / "grain_preview.png")
    print("wrote res/grain.texture, res/grain.material, internal/grain_preview.png")


if __name__ == "__main__":
    main()
