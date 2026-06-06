#!/usr/bin/env bash
set -euo pipefail

folder="${1:-.}"
cell_size="${2:-128}"

if [[ ! -d "$folder" ]]; then
  echo "Animation sheet folder not found: $folder" >&2
  exit 1
fi

if [[ ! "$cell_size" =~ ^[0-9]+$ || "$cell_size" -le 0 ]]; then
  echo "Cell size must be a positive integer: $cell_size" >&2
  exit 1
fi

python_cmd=""
for candidate in python3 python python.exe py; do
  if command -v "$candidate" >/dev/null 2>&1; then
    python_cmd="$candidate"
    break
  fi
done

if [[ -z "$python_cmd" ]]; then
  echo "Python is required to inspect PNG headers, but no Python executable was found." >&2
  exit 1
fi

"$python_cmd" - "$folder" "$cell_size" <<'PY'
from __future__ import annotations

import struct
import sys
from collections import Counter
from pathlib import Path

folder = Path(sys.argv[1])
cell_size = int(sys.argv[2])
png_signature = b"\x89PNG\r\n\x1a\n"

def read_png_info(path: Path):
    with path.open("rb") as fh:
        signature = fh.read(8)
        if signature != png_signature:
            raise ValueError("not a PNG file")
        length = struct.unpack(">I", fh.read(4))[0]
        chunk_type = fh.read(4)
        if chunk_type != b"IHDR" or length < 13:
            raise ValueError("missing IHDR")
        data = fh.read(length)
        width, height, bit_depth, color_type = struct.unpack(">IIBB", data[:10])
        has_alpha = color_type in (4, 6)
        return width, height, bit_depth, color_type, has_alpha

files = sorted(folder.glob("*.png"))
if not files:
    print(f"No PNG animation sheets found under: {folder}")
    sys.exit(0)

layouts = Counter()
status = 0

print(f"Animation sheet inspection: {folder}")
print(f"Expected cell size: {cell_size}x{cell_size}")
print()
print("| File | Size | Grid | Alpha | Notes |")
print("| --- | --- | --- | --- | --- |")

for path in files:
    try:
        width, height, bit_depth, color_type, has_alpha = read_png_info(path)
    except Exception as exc:
        print(f"| {path.name} | unknown | unknown | unknown | {exc} |")
        status = 1
        continue

    notes = []
    if width % cell_size != 0 or height % cell_size != 0:
        notes.append("not divisible by cell size")
        status = 1

    columns = width // cell_size if width % cell_size == 0 else "custom"
    rows = height // cell_size if height % cell_size == 0 else "custom"
    if isinstance(columns, int) and isinstance(rows, int):
        layouts[(columns, rows)] += 1

    if not has_alpha:
        notes.append("no alpha channel")

    note_text = ", ".join(notes) if notes else "ok"
    print(f"| {path.name} | {width}x{height} | {columns}x{rows} | {has_alpha} | {note_text} |")

print()
if layouts:
    common = ", ".join(f"{cols}x{rows} ({count})" for (cols, rows), count in layouts.most_common())
    print(f"Detected grids: {common}")

if len(layouts) == 1:
    (columns, rows), count = next(iter(layouts.items()))
    print(f"Common profile: {columns} frame columns x {rows} direction/action rows across {count} sheet(s).")

sys.exit(status)
PY
