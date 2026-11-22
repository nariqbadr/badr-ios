#!/usr/bin/env python3
"""Mosques of one OpenStreetMap extract (already cut down by `osmium tags-filter` to places of worship and the nodes and
ways they use) into part-<name>.json for tools/merge.py: [id, lat, lng, name, name:ar, name:en, area, street] per 1-degree
cell. A way or a relation is placed at the middle of its points. Data © OpenStreetMap contributors, ODbL 1.0."""
import json, math, sys
import osmium

src, out = sys.argv[1], sys.argv[2]
cells, seen = {}, set()
ways = {}   # way id -> (sum lat, sum lon, n) for the relations built from them

def mosque(t):
    return (t.get("amenity") == "place_of_worship" and t.get("religion") == "muslim") or t.get("building") == "mosque"

def put(key, la, lo, t):
    if key in seen: return
    seen.add(key)
    area = t.get("addr:suburb") or t.get("addr:city") or ""
    row = [key, round(la, 5), round(lo, 5), t.get("name", ""), t.get("name:ar", ""), t.get("name:en", ""), area, t.get("addr:street", "")]
    while row and row[-1] == "": row.pop()
    cells.setdefault(f"{math.floor(la)}_{math.floor(lo)}", []).append(row)

class H(osmium.SimpleHandler):
    def node(self, n):
        if mosque(n.tags) and n.location.valid():
            put("n" + str(n.id), n.location.lat, n.location.lon, dict(n.tags))
    def way(self, w):
        sa = so = 0.0; k = 0
        for nd in w.nodes:
            if nd.location.valid(): sa += nd.location.lat; so += nd.location.lon; k += 1
        if not k: return
        ways[w.id] = (sa, so, k)
        if mosque(w.tags): put("w" + str(w.id), sa / k, so / k, dict(w.tags))
    def relation(self, r):
        if not mosque(r.tags): return
        sa = so = 0.0; k = 0
        for m in r.members:
            if m.type == "w" and m.ref in ways: a, b, c = ways[m.ref]; sa += a; so += b; k += c
        if k: put("r" + str(r.id), sa / k, so / k, dict(r.tags))

H().apply_file(src, locations=True, idx="flex_mem")
name = sys.argv[3]
json.dump({"cells": cells, "gaps": [], "count": len(seen)}, open(f"{out}/part-{name}.json", "w"), ensure_ascii=False, separators=(",", ":"))
print("DONE", name, len(seen), "mosques in", len(cells), "cells", flush=True)
