#!/usr/bin/env python3
"""Generate deterministic, opaque test icons; optionally compile with Apple's actool."""
import argparse
import json
from pathlib import Path
import struct
import subprocess
import zlib


def png(size):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            mark = size // 3 <= x < 2 * size // 3 or size // 3 <= y < 2 * size // 3
            rows.extend((240, 248, 255) if mark else (24, 74, 120))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def generate(root):
    info = {'author': 'xtool', 'version': 1}
    for platform in ('iphoneos', 'watchos'):
        catalog = root / (platform + '.xcassets')
        icons = catalog / 'AppIcon.appiconset'
        icons.mkdir(parents=True, exist_ok=True)
        (catalog / 'Contents.json').write_text(json.dumps({'info': info}))
        entries = []
        variants = [('iphone', size, scale) for size in (20, 29, 40, 60) for scale in (2, 3)]
        variants += [('ipad', size, scale) for size in (20, 29, 40, 76) for scale in (1, 2)]
        variants += [('ipad', 83.5, 2), ('ios-marketing', 1024, 1)]
        if platform == 'watchos':
            variants = [('universal', 1024, 1)]
        for idiom, size, scale in variants:
            filename = f'{idiom}-{size}-{scale}.png'
            (icons / filename).write_bytes(png(int(size * scale)))
            entry = {'idiom': idiom, 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': filename}
            if platform == 'watchos':
                entry['platform'] = 'watchos'
            entries.append(entry)
        (icons / 'Contents.json').write_text(json.dumps({'info': info, 'images': entries}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--compile', action='store_true', help='Requires macOS and Xcode')
    args = parser.parse_args()
    generate(args.directory)
    if args.compile:
        for platform, minimum, devices in [('iphoneos', '17.0', ['iphone', 'ipad']), ('watchos', '26.0', ['watch'])]:
            destination = args.directory / platform
            destination.mkdir(exist_ok=True)
            command = ['xcrun', 'actool', '--compile', str(destination), '--platform', platform,
                       '--minimum-deployment-target', minimum, '--app-icon', 'AppIcon',
                       '--output-partial-info-plist', str(destination / 'Info.plist')]
            for device in devices:
                command += ['--target-device', device]
            command.append(str(args.directory / (platform + '.xcassets')))
            subprocess.run(command, check=True)
            assert (destination / 'Assets.car').stat().st_size > 0


if __name__ == '__main__':
    main()
