"""Builds what the sky fix ships, in res/: five skies of the mod's own, drawn here, on the dome the game's
engine keeps for its editor, and the render config with the clear pass fixed.

Usage: python tools/build_sky.py [path to Helldivers/contents]

Why a fix: the game was made to be seen from above, so where a camera looks past the level nothing is
drawn there, and the picture keeps what was there before: smears of old frames. The render config's
clear pass empties three of the five picture targets each frame and leaves albedo and normal alone. The
fix clears all five, as the Third Person Camera mod for this game found, and a dome draws a sky around.

The dome is core/editor_slave/units/skydome/skydome, in the ship's package: a hemisphere 500 m across
whose one material tiles one texture, with an `intensity` (2). Its own texture is the editor's grey
checker. Each sky here is a copy of that unit whose only change is the name of its material, and a copy
of that material whose only change is the name of its texture. The textures are drawn by this script:
seamless clouds over a colour, or stars, uncompressed with every mip, as the dome's own is.

Needs numpy and Pillow. Writes res/sky_<name>.unit, .material and .texture, res/render_config.bin, and
internal/sky_preview.png.
"""
import io
import struct
import sys
import zlib
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "res"
CONTENTS = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Program Files (x86)\Steam\steamapps\common\Helldivers\contents")

DOME = "core/editor_slave/units/skydome/skydome"
SHIP_BUNDLE = "ec181385e7000cf1"      # resource_packages/menu
RENDER_BUNDLE = "1a9c33dcd0301dfd"    # core rendering: the render config and the shaders
SIZE = 512
SKIES = ["day", "dawn", "dusk", "night", "overcast"]


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


def bundle_entries(path):
    """A bundle's resources: (type, name, data of the first variant)."""
    data = path.read_bytes()
    if len(data) < 12 or struct.unpack_from("<I", data, 0)[0] != 0xF0000004:
        return
    total = struct.unpack_from("<I", data, 4)[0]
    raw, pos = bytearray(), 12
    while pos < len(data) and len(raw) < total:
        (size,) = struct.unpack_from("<I", data, pos)
        pos += 4
        chunk = data[pos:pos + size]
        pos += size
        raw += chunk if size == 0x10000 else zlib.decompress(chunk)
    (count,) = struct.unpack_from("<I", raw, 0)
    pos = 260 + count * 16
    for _ in range(count):
        kind, name, variants, _ = struct.unpack_from("<QQII", raw, pos)
        pos += 24
        heads = [struct.unpack_from("<III", raw, pos + 12 * i) for i in range(variants)]
        pos += 12 * variants
        first = None
        for _, size, _ in heads:
            if first is None:
                first = bytes(raw[pos:pos + size])
            pos += size
        yield kind, name, first


def find(bundle, kind, name_hash):
    for k, n, data in bundle_entries(CONTENTS / bundle):
        if k == murmur64(kind.encode()) and n == name_hash:
            return data
    raise SystemExit(f"no {kind} {name_hash:016x} in {bundle}")


def replace_u64(data, old, new, expect=1):
    out, found, i = bytearray(data), 0, 0
    old_b, new_b = struct.pack("<Q", old), struct.pack("<Q", new)
    while True:
        i = out.find(old_b, i)
        if i < 0:
            break
        out[i:i + 8] = new_b
        found += 1
        i += 8
    if found != expect:
        raise SystemExit(f"expected {expect} of {old:016x}, found {found}")
    return bytes(out)


# Drawing. Noise that tiles: a small random lattice, tiled three by three, smoothed up and cut from the
# middle, so its edges meet.
def tiling_noise(rng, cells, size):
    lattice = rng.random((cells, cells)).astype(np.float32)
    big = Image.fromarray(np.tile(lattice, (3, 3)) * 255).convert("F")
    big = big.resize((size * 3, size * 3), Image.Resampling.BICUBIC)
    return np.asarray(big)[size:size * 2, size:size * 2] / 255.0


def fbm(rng, size, base=4, octaves=6):
    total, weight, norm = np.zeros((size, size), np.float32), 1.0, 0.0
    for o in range(octaves):
        total += tiling_noise(rng, base * 2 ** o, size) * weight
        norm += weight
        weight *= 0.5
    return total / norm


def smooth(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return a[None, None, :] * (1 - t[..., None]) + b[None, None, :] * t[..., None]


def clouds(seed, sky, cloud, shade, cover, soft):
    rng = np.random.default_rng(seed)
    n = fbm(rng, SIZE)
    detail = fbm(rng, SIZE, base=16, octaves=3)
    field = n * 0.85 + detail * 0.15
    # cover is the share of the sky in cloud: the edge sits at that quantile, and soft widens it.
    edge = float(np.quantile(field, 1 - cover))
    spread = float(np.quantile(field, min(0.999, 1 - cover + soft))) - edge
    density = smooth(edge, edge + max(spread, 1e-3), field)
    detail = (detail - detail.min()) / max(1e-6, detail.max() - detail.min())
    # Cloud bottoms darker than their tops, as lit from above.
    lit = np.clip(detail * 1.4 - 0.2, 0, 1)
    colour = mix(np.array(shade, np.float32), np.array(cloud, np.float32), lit)
    out = np.broadcast_to(np.array(sky, np.float32), (SIZE, SIZE, 3))
    out = out * (1 - density[..., None]) + colour * density[..., None]
    return np.clip(out, 0, 255).astype(np.uint8)


def night(seed):
    rng = np.random.default_rng(seed)
    base = clouds(seed, (9, 13, 30), (34, 40, 66), (16, 20, 40), 0.35, 0.35).astype(np.float32)
    stars = np.zeros((SIZE, SIZE), np.float32)
    count = 1400
    xs, ys = rng.integers(0, SIZE, count), rng.integers(0, SIZE, count)
    bright = rng.random(count) ** 3
    stars[ys, xs] = 80 + bright * 175
    # A few bigger ones, a pixel around.
    for x, y in zip(xs[:60], ys[:60]):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            stars[(y + dy) % SIZE, (x + dx) % SIZE] = max(stars[(y + dy) % SIZE, (x + dx) % SIZE], 70)
    tint = np.array((0.9, 0.95, 1.0), np.float32)
    out = np.maximum(base, stars[..., None] * tint[None, None, :])
    return np.clip(out, 0, 255).astype(np.uint8)


def draw(name):
    if name == "day":
        return clouds(11, (82, 132, 200), (246, 248, 252), (176, 188, 206), 0.42, 0.22)
    if name == "dawn":
        return clouds(23, (214, 160, 168), (255, 226, 210), (170, 120, 150), 0.40, 0.25)
    if name == "dusk":
        return clouds(37, (206, 112, 84), (255, 182, 120), (112, 62, 96), 0.45, 0.25)
    if name == "overcast":
        return clouds(41, (128, 134, 142), (196, 200, 206), (96, 100, 108), 0.80, 0.35)
    return night(53)


def texture(rgb):
    """Uncompressed BGRA with every mip, and the four-byte category every texture resource ends with."""
    image = Image.fromarray(rgb, "RGB").convert("RGBA")
    mips = [image]
    while mips[-1].size != (1, 1):
        w, h = mips[-1].size
        mips.append(mips[-1].resize((max(1, w // 2), max(1, h // 2)), Image.Resampling.BOX))
    header = bytearray(128)
    header[:4] = b"DDS "
    struct.pack_into("<IIIIIII", header, 4, 124, 0x0002100F, SIZE, SIZE, SIZE * 4, 0, len(mips))
    header[60:64], header[68:72] = b"UVER", b"NVTT"
    struct.pack_into("<I", header, 72, 0x00020100)
    struct.pack_into("<IIIIIIII", header, 76, 32, 0x41, 0, 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    struct.pack_into("<I", header, 108, 0x00401008)
    body = b"".join(np.asarray(m)[..., [2, 1, 0, 3]].tobytes() for m in mips)
    return bytes(header) + body + bytes(4)


def fixed_render_config(data):
    """The clear pass's render targets, with albedo and normal added: a new string at the end, and the
    pass pointed at it. Offsets in the config count from its start."""
    old = b"mask self_illumination light_accumulation\0"
    new = b"albedo normal mask self_illumination light_accumulation\0"
    if data.endswith(new):
        raise SystemExit("the render config is already fixed")
    at = data.find(old)
    clear = data.find(b"clear_pass\0")
    if at < 0 or clear < 0:
        raise SystemExit("the render config has no clear pass to fix")
    out = bytearray(data)
    patched = 0
    for i in range(0, len(data) - 3, 4):
        if struct.unpack_from("<I", data, i)[0] == clear:
            for j in range(i + 4, min(i + 48, len(data) - 3), 4):
                if struct.unpack_from("<I", data, j)[0] == at:
                    struct.pack_into("<I", out, j, len(data))
                    patched += 1
                    break
    if patched != 1:
        raise SystemExit(f"expected one clear pass to fix, found {patched}")
    return bytes(out) + new


def main():
    RES.mkdir(exist_ok=True)
    dome = murmur64(DOME.encode())
    unit = find(SHIP_BUNDLE, "unit", dome)
    material = find(SHIP_BUNDLE, "material", dome)
    checker = struct.unpack_from("<Q", material, 32)[0]
    previews = []
    for name in SKIES:
        base = f"photomode/sky/{name}"
        rgb = draw(name)
        previews.append(Image.fromarray(rgb, "RGB").resize((256, 256)))
        (RES / f"sky_{name}.texture").write_bytes(texture(rgb))
        (RES / f"sky_{name}.material").write_bytes(replace_u64(material, checker, murmur64((base + "_map").encode())))
        (RES / f"sky_{name}.unit").write_bytes(replace_u64(unit, dome, murmur64(base.encode())))
        print("sky", name)
    render = find(RENDER_BUNDLE, "render_config", int(RENDER_BUNDLE, 16))
    (RES / "render_config.bin").write_bytes(fixed_render_config(render))
    print("render config", len(render), "->", len(render) + len(b"albedo normal mask self_illumination light_accumulation\0"))
    sheet = Image.new("RGB", (256 * len(previews), 256))
    for i, p in enumerate(previews):
        sheet.paste(p, (256 * i, 0))
    (ROOT / "internal").mkdir(exist_ok=True)
    sheet.save(ROOT / "internal" / "sky_preview.png")


if __name__ == "__main__":
    main()
