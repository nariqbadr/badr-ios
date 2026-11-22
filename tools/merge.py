#!/usr/bin/env python3
"""Joins the bands of tools/extract.py into t/<lat>_<lon>.json, meta.json and cells.json; refuses when a band has gaps
(a missing cell reads as "no mosques here" in the apps, so a hole must never be published)."""
import glob, json, sys, time
src, out = sys.argv[1], sys.argv[2]
import os; os.makedirs(out + "/t", exist_ok=True)
cells, seen, gaps, bands = {}, set(), [], 0
for p in sorted(glob.glob(src + "/**/part-*.json", recursive=True)):
    j = json.load(open(p)); bands += 1; gaps += j.get("gaps", [])
    for k, rows in j["cells"].items():
        for r in rows:
            if r[0] in seen: continue
            seen.add(r[0]); cells.setdefault(k, []).append(r)
if bands != 14: sys.exit(f"only {bands} bands of 14")
if gaps: sys.exit(f"gaps: {gaps}")
for k, rows in cells.items():
    rows.sort(key=lambda r: (r[1], r[2]))
    with open(f"{out}/t/{k}.json", "w") as f: json.dump(rows, f, ensure_ascii=False, separators=(",", ":"))
meta = {"v": 1, "at": int(time.time()), "count": len(seen), "cells": len(cells), "cell": 1,
        "fields": ["id", "lat", "lng", "name", "ar", "en", "area", "street"],
        "attribution": "© OpenStreetMap contributors", "license": "ODbL 1.0 https://opendatacommons.org/licenses/odbl/"}
json.dump(meta, open(f"{out}/meta.json", "w"))
json.dump(sorted(cells), open(f"{out}/cells.json", "w"), separators=(",", ":"))
print("DONE", meta)
