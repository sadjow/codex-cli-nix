#!/usr/bin/env python3
import pathlib
import re
import struct
import sys


def check_package(root):
    root = pathlib.Path(root)
    if not root.is_dir():
        raise ValueError(f"Package directory is missing: {root}")
    files = [path for path in root.rglob('*') if path.is_file()]
    if not files:
        raise ValueError(f"Package directory is empty: {root}")
    for path in files:
        data = path.read_bytes()
        if re.search(rb'/nix/store/[0-9a-z]{32}-', data):
            raise ValueError(f"Store dependency in {path.relative_to(root)}")
        if data[:4] == b'\x7fELF':
            if data[4:6] != b'\x02\x01':
                raise ValueError(f"Unsupported ELF format: {path.relative_to(root)}")
            offset = struct.unpack_from('<Q', data, 32)[0]
            size, count = struct.unpack_from('<HH', data, 54)
            for index in range(count):
                kind = struct.unpack_from('<I', data, offset + index * size)[0]
                if kind == 3:
                    raise ValueError(f"Dynamic ELF dependency in {path.relative_to(root)}")


if __name__ == '__main__':
    check_package(sys.argv[1])
