#!/usr/bin/env python3
"""Measures the copy in Metadata.md and ReviewNotes.md against Apple's limits."""
import pathlib, re, sys

here = pathlib.Path(__file__).parent
meta = (here / "Metadata.md").read_text()
notes = (here / "ReviewNotes.md").read_text()

def block(text, heading):
    return re.search(rf"## {re.escape(heading)}.*?```\n(.*?)\n```", text, re.S).group(1)

def cell(text, field):
    return re.search(rf"\| {re.escape(field)} \| \d+ \| `(.*?)` \|", text).group(1)

checks = [
    ("Name", cell(meta, "Name"), 30, len),
    ("Subtitle", cell(meta, "Subtitle"), 30, len),
    ("Promotional text", block(meta, "Promotional text"), 170, len),
    ("Description", block(meta, "Description"), 4000, len),
    ("Keywords", block(meta, "Keywords"), 100, lambda s: len(s.encode())),
    ("Review notes", block(notes, "Notes"), 4000, lambda s: len(s.encode())),
]
failed = False
for name, text, limit, measure in checks:
    size = measure(text)
    failed |= size > limit
    print(f"{'OK  ' if size <= limit else 'OVER'} {name}: {size}/{limit}")
sys.exit(1 if failed else 0)
