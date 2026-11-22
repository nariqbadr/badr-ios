#!/usr/bin/env python3
"""The mosques of Egypt for «بيوت الله»: OpenStreetMap (all of it, the newest edits included) and Overture's places
(Meta, Microsoft, Foursquare…) put together — one entry per mosque, unnamed ones left out — cut into 0.1° tiles."""
import json, math, os, re, subprocess, sys, datetime
OUT = sys.argv[1]
BB = (24.6, 21.6, 37.0, 31.8)  # Egypt: lng min, lat min, lng max, lat max
AR = re.compile(r"[ء-ي]")
def dist(a, b):
    return math.hypot((a[0] - b[0]) * 111320, (a[1] - b[1]) * 111320 * math.cos(math.radians(a[0])))

# ---- OpenStreetMap
osm = []
for line in open("pw.geojsonseq", encoding="utf-8"):
    line = line.strip().lstrip("\x1e")
    if not line: continue
    f = json.loads(line); p = f.get("properties", {}); g = f.get("geometry") or {}
    rel, bld, nm = p.get("religion", ""), p.get("building", ""), (p.get("name") or "").strip()
    if not (rel == "muslim" or bld == "mosque" or (not rel and re.search(r"مسجد|جامع|زاوية|مصلى", nm))): continue
    if rel and rel != "muslim": continue
    c = g.get("coordinates")
    if g.get("type") == "Point": lng, lat = c
    else:
        pts = []
        def walk(x):
            if isinstance(x[0], (int, float)): pts.append(x)
            else:
                for y in x: walk(y)
        walk(c)
        if not pts: continue
        lng = sum(q[0] for q in pts) / len(pts); lat = sum(q[1] for q in pts) / len(pts)
    ar, en = (p.get("name:ar") or "").strip(), (p.get("name:en") or "").strip()
    if not (nm or ar or en): continue
    if nm in ("مسجد", "جامع", "Mosque", "mosque") and not ar and not en: continue
    tid = p.get("@type", "n")[:1] + str(p.get("@id", ""))
    osm.append({"id": tid, "lat": lat, "lng": lng, "name": nm, "ar": ar, "en": en, "street": (p.get("addr:street") or "").strip()})
print("osm named mosques (extract)", len(osm))

# ---- the edits made since the extract (live from OpenStreetMap): a mosque added or renamed today replaces / joins
try:
    rec = json.load(open("recent.json", encoding="utf-8")).get("elements", [])
except Exception as e:
    rec = []; print("no recent edits:", e)
byid = {m["id"]: i for i, m in enumerate(osm)}
fresh = 0
for e in rec:
    t = e.get("tags", {}); c = e.get("center") or {}
    lat = e.get("lat", c.get("lat")); lng = e.get("lon", c.get("lon"))
    if lat is None or lng is None: continue
    rel, bld, nm = t.get("religion", ""), t.get("building", ""), (t.get("name") or "").strip()
    if not (rel == "muslim" or bld == "mosque"): continue
    tid = e["type"][:1] + str(e["id"])
    m = {"id": tid, "lat": lat, "lng": lng, "name": nm, "ar": (t.get("name:ar") or "").strip(), "en": (t.get("name:en") or "").strip(), "street": (t.get("addr:street") or "").strip()}
    named = bool(m["name"] or m["ar"] or m["en"]) and not (nm in ("مسجد", "جامع") and not m["ar"] and not m["en"])
    if tid in byid:
        if named: osm[byid[tid]] = m
        else: osm[byid[tid]] = None
    elif named: osm.append(m); fresh += 1
osm = [m for m in osm if m]
print("recent edits", len(rec), "new mosques", fresh, "osm now", len(osm))

# ---- Overture
import duckdb
rel = subprocess.check_output("aws s3 ls --no-sign-request s3://overturemaps-us-west-2/release/ | awk '{print $2}' | tr -d / | sort | tail -1", shell=True).decode().strip()
con = duckdb.connect()
con.execute("INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial; SET s3_region='us-west-2';")
q = f"""
SELECT id, names.primary AS name, CAST(names.common AS JSON) AS common, CAST(basic_category AS VARCHAR) AS cat, CAST(taxonomy AS VARCHAR) AS tax,
       confidence, ST_Y(geometry) AS lat, ST_X(geometry) AS lng, CAST(operating_status AS VARCHAR) AS st
FROM read_parquet('s3://overturemaps-us-west-2/release/{rel}/theme=places/type=place/*', hive_partitioning=1)
WHERE bbox.xmin BETWEEN {BB[0]} AND {BB[2]} AND bbox.ymin BETWEEN {BB[1]} AND {BB[3]}
  AND (basic_category = 'muslim_place_of_worship' OR CAST(taxonomy AS VARCHAR) LIKE '%mosque%' OR CAST(taxonomy AS VARCHAR) LIKE '%muslim_place_of_worship%')
"""
rows = con.execute(q).fetchall()
print("overture release", rel, "rows", len(rows))
ov = []
for oid, name, common, cat, tax, conf, lat, lng, st in rows:
    if st and "closed" in st.lower(): continue
    if conf is not None and conf < 0.45: continue
    name = (name or "").strip()
    try: cm = json.loads(common) if common else {}
    except Exception: cm = {}
    ar = (cm.get("ar") or "").strip() if isinstance(cm, dict) else ""
    en = (cm.get("en") or "").strip() if isinstance(cm, dict) else ""
    if not (name or ar or en): continue
    # a page that only mentions a mosque (an events hall, a shop, a charity at the mosque) is not the mosque
    if re.search(r"دار مناسبات|دار المناسبات|جمعية|مكتب|محل|شركة|صيدلية|مدرسة|حضانة|مكتبة|events?|shop|store|school|pharmacy", name, re.I): continue
    ov.append({"id": "o" + oid[:16], "lat": lat, "lng": lng, "name": name, "ar": ar if ar != name else "", "en": en if en != name else "", "street": ""})
print("overture mosques", len(ov))

# ---- one entry per mosque: OpenStreetMap first; an Overture place within 40 m of one of its mosques is the same one
cell = {}
def key(lat, lng): return (int(lat * 500), int(lng * 500))  # ~200 m cells for the neighbour search
def near(m, r):
    k = key(m["lat"], m["lng"])
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for o in cell.get((k[0] + dx, k[1] + dy), []):
                if dist((m["lat"], m["lng"]), (o["lat"], o["lng"])) < r: return o
    return None
def norm(n):
    n = re.sub(r"[\u064B-\u065F\u0670\u0640_\-.,،]", " ", n or "")
    n = re.sub(r"[أإآٱ]", "ا", n).replace("ى", "ي").replace("ة", "ه")
    n = re.sub(r"\b(مسجد|جامع|الشيخ|سيدنا|السيده|السيدة)\b", " ", n)
    n = re.sub(r"\b(mosque|masjid|masjed|el|al)\b", " ", n.lower())
    return re.sub(r"\s+", " ", n).strip()
def same_name(m, r):
    k = key(m["lat"], m["lng"]); a = norm(m["name"] or m["ar"] or m["en"])
    if len(a) < 3: return False
    for dx in range(-2, 3):
        for dy in range(-2, 3):
            for o in cell.get((k[0] + dx, k[1] + dy), []):
                if dist((m["lat"], m["lng"]), (o["lat"], o["lng"])) < r and a in (norm(o["name"]), norm(o["ar"]), norm(o["en"])): return True
    return False
out = []
for m in osm:
    if near(m, 12): continue  # its point and its building outline
    cell.setdefault(key(m["lat"], m["lng"]), []).append(m); out.append(m)
added = 0
for m in sorted(ov, key=lambda x: -len(x["name"])):
    if near(m, 40) or same_name(m, 400): continue
    cell.setdefault(key(m["lat"], m["lng"]), []).append(m); out.append(m); added += 1
print("merged", len(out), "overture added", added)

# ---- tiles of 0.1°
tiles = {}
for m in out:
    t = f"{math.floor(m['lat'] * 10)}_{math.floor(m['lng'] * 10)}"
    tiles.setdefault(t, []).append([m["id"], round(m["lat"], 6), round(m["lng"], 6), m["name"], m["ar"], m["en"], m["street"]])
os.makedirs(os.path.join(OUT, "t"), exist_ok=True)
for t, l in tiles.items():
    with open(os.path.join(OUT, "t", t + ".json"), "w", encoding="utf-8") as f: json.dump(l, f, ensure_ascii=False, separators=(",", ":"))
v = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ")
json.dump({"v": v, "bbox": BB, "count": len(out), "osm": len(osm), "overture": added, "tiles": sorted(tiles)}, open(os.path.join(OUT, "meta.json"), "w"), separators=(",", ":"))
print("tiles", len(tiles), "version", v)
