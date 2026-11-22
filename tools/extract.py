#!/usr/bin/env python3
"""Every mosque in OpenStreetMap, cut into 1-degree cells (t/<lat>_<lon>.json) for the Badr apps.
Data © OpenStreetMap contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright)."""
import json, math, os, sys, time, urllib.request, urllib.parse
EPS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter", "https://overpass.private.coffee/api/interpreter"]
UA = "BadrTilawat-mosque-tiles/1.0 (+https://bawazirquran.com)"
OUT = sys.argv[1] if len(sys.argv) > 1 else "out"
os.makedirs(OUT + "/t", exist_ok=True)
cells = {}
seen = set()
ep_i = 0
def q(s, w, n, e):
    global ep_i
    bb = f"({s},{w},{n},{e})"
    data = f'[out:json][timeout:600][maxsize:1073741824];(nwr["amenity"="place_of_worship"]["religion"="muslim"]{bb};nwr["building"="mosque"]{bb};);out center tags;'
    for attempt in range(6):
        ep = EPS[ep_i % len(EPS)]
        try:
            req = urllib.request.Request(ep, data=urllib.parse.urlencode({"data": data}).encode(), headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=700) as r:
                j = json.load(r)
            if j.get("remark") and "runtime error" in j["remark"]:
                raise RuntimeError(j["remark"][:200])
            return j.get("elements", [])
        except Exception as ex:
            print(f"  retry {attempt} {bb} via {ep}: {ex}", flush=True)
            ep_i += 1
            time.sleep(10 * (attempt + 1))
    return None
def put(el):
    t = el.get("tags", {})
    key = el["type"][0] + str(el["id"])
    if key in seen: return
    if "lat" in el: la, lo = el["lat"], el["lon"]
    elif "center" in el: la, lo = el["center"]["lat"], el["center"]["lon"]
    else: return
    seen.add(key)
    area = t.get("addr:suburb") or t.get("addr:city") or ""
    row = [key, round(la, 5), round(lo, 5), t.get("name", ""), t.get("name:ar", ""), t.get("name:en", ""), area, t.get("addr:street", "")]
    while row and row[-1] == "": row.pop()
    cells.setdefault(f"{math.floor(la)}_{math.floor(lo)}", []).append(row)
def box(s, w, n, e, depth=0):
    els = q(s, w, n, e)
    if els is None:
        if depth < 4:
            ms, mw = (s + n) / 2, (w + e) / 2
            for b in ((s, w, ms, mw), (s, mw, ms, e), (ms, w, n, mw), (ms, mw, n, e)): box(*b, depth=depth + 1)
        else: print(f"GAVE UP {s},{w},{n},{e}", flush=True)
        return
    for el in els: put(el)
    print(f"{s},{w},{n},{e}: {len(els)} (total {len(seen)})", flush=True)
    time.sleep(2)
step = 10
for s in range(-60, 80, step):
    for w in range(-180, 180, step):
        box(s, w, s + step, w + step)
for k, rows in cells.items():
    rows.sort(key=lambda r: (r[1], r[2]))
    with open(f"{OUT}/t/{k}.json", "w") as f: json.dump(rows, f, ensure_ascii=False, separators=(",", ":"))
meta = {"v": 1, "at": int(time.time()), "count": len(seen), "cells": len(cells), "cell": 1,
        "fields": ["id", "lat", "lng", "name", "ar", "en", "area", "street"],
        "attribution": "© OpenStreetMap contributors", "license": "ODbL 1.0 https://opendatacommons.org/licenses/odbl/"}
with open(f"{OUT}/meta.json", "w") as f: json.dump(meta, f)
with open(f"{OUT}/cells.json", "w") as f: json.dump(sorted(cells), f, separators=(",", ":"))
print("DONE", meta, flush=True)
