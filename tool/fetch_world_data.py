#!/usr/bin/env python3
"""Build offline world country + Admin-1 province data for World Dominion.

The build downloads source data only while preparing the app on GitHub Actions.
The produced JSON assets are bundled into the APK so normal single-player map use is offline.

Sources:
- mledoze/countries for ISO country metadata, population, capital and land borders.
- Natural Earth 1:10m Admin-1 for province/state names, Arabic/English labels and polygons.
"""
from __future__ import annotations
import json, math, os, pathlib, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
COUNTRIES = 'https://raw.githubusercontent.com/mledoze/countries/master/countries.json'
ADMIN1 = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_admin_1_states_provinces.geojson'


def load(url: str):
    req = urllib.request.Request(url, headers={'User-Agent': 'World-Dominion-Build/1.5'})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def perpendicular_distance(p, a, b):
    if a == b:
        return math.hypot(p[0]-a[0], p[1]-a[1])
    x, y = p; x1, y1 = a; x2, y2 = b
    dx, dy = x2-x1, y2-y1
    t = max(0.0, min(1.0, ((x-x1)*dx + (y-y1)*dy) / (dx*dx + dy*dy)))
    px, py = x1+t*dx, y1+t*dy
    return math.hypot(x-px, y-py)


def rdp(points, epsilon=0.10):
    if len(points) <= 4:
        return points
    first, last = points[0], points[-1]
    max_dist, index = 0.0, 0
    for i in range(1, len(points)-1):
        d = perpendicular_distance(points[i], first, last)
        if d > max_dist:
            index, max_dist = i, d
    if max_dist > epsilon:
        left = rdp(points[:index+1], epsilon)
        right = rdp(points[index:], epsilon)
        return left[:-1] + right
    return [first, last]


def compact_ring(raw):
    pts = []
    for p in raw:
        if not isinstance(p, list) or len(p) < 2:
            continue
        try:
            lon, lat = round(float(p[0]), 3), round(float(p[1]), 3)
        except Exception:
            continue
        if not pts or pts[-1] != [lon, lat]:
            pts.append([lon, lat])
    if len(pts) < 4:
        return []
    if pts[0] != pts[-1]:
        pts.append(pts[0])
    pts = rdp(pts, 0.10)
    if pts[0] != pts[-1]:
        pts.append(pts[0])
    # Hard cap for very complex coastlines. Keeps mobile rendering predictable.
    if len(pts) > 220:
        step = max(1, math.ceil((len(pts)-1)/219))
        pts = pts[:-1:step] + [pts[-1]]
    return pts if len(pts) >= 4 else []


def geometry_rings(geom):
    if not isinstance(geom, dict):
        return []
    kind, coords = geom.get('type'), geom.get('coordinates') or []
    polygons = coords if kind == 'MultiPolygon' else [coords] if kind == 'Polygon' else []
    out = []
    for poly in polygons:
        if not poly:
            continue
        outer = compact_ring(poly[0])
        if outer:
            out.append(outer)
    return out



def terrain_and_climate(a3: str, name: str, lat: float | None, lng: float | None):
    """Deterministic gameplay classification from admin centroid.

    This is intentionally conservative: it gives the simulation a useful physical
    baseline without pretending to be a high-resolution terrain survey.
    """
    lat = float(lat or 0); lng = float(lng or 0); n = (name or '').casefold()
    arid = {'DZA','EGY','LBY','MAR','MRT','MLI','NER','TCD','SDN','SAU','YEM','OMN','ARE','QAT','BHR','KWT','JOR','IRQ','IRN','AFG','PAK','NAM','BWA','AUS'}
    tropical = {'BRA','COL','VEN','ECU','PER','BOL','GUY','SUR','IDN','MYS','PHL','THA','VNM','KHM','LAO','MMR','BGD','IND','LKA','COD','COG','GAB','CMR','NGA','GHA','CIV','LBR','SLE','GIN','UGA','KEN','TZA','MOZ','MDG'}
    mountain_countries = {'AFG','PAK','NPL','BTN','CHE','AUT','GEO','ARM','KGZ','TJK','PER','BOL','CHL','ETH','RWA','BDI'}
    if abs(lat) >= 60: climate='arctic'
    elif a3 in arid: climate='arid'
    elif a3 in tropical and abs(lat) < 27: climate='tropical'
    elif abs(lat) >= 42: climate='continental'
    else: climate='temperate'
    if any(k in n for k in ('city','capital','district','metro','urban')): terrain='urban'
    elif a3 in mountain_countries or any(k in n for k in ('mount','highland','alps','himal','andes','tibet','kashmir')): terrain='mountains'
    elif climate=='arctic': terrain='arctic'
    elif climate=='arid': terrain='desert'
    elif climate=='tropical' and abs(lat) < 15: terrain='jungle'
    elif any(k in n for k in ('forest','wood','jungle')): terrain='forest'
    elif any(k in n for k in ('hill','plateau')): terrain='hills'
    else: terrain='plains'
    return terrain, climate

def clean_code(value):
    value = str(value or '').strip().upper()
    return value if len(value) <= 24 else value[:24]


countries_file=os.environ.get('WD_COUNTRIES_FILE','').strip(); admin_file=os.environ.get('WD_ADMIN1_FILE','').strip()
countries = json.loads(pathlib.Path(countries_file).read_text(encoding='utf-8')) if countries_file else load(COUNTRIES)
admin_geo = json.loads(pathlib.Path(admin_file).read_text(encoding='utf-8')) if admin_file else load(ADMIN1)
features = admin_geo.get('features') or []
admin_by_country = {}
shape_countries = {}
for f in features:
    p = f.get('properties') or {}
    a3 = clean_code(p.get('adm0_a3') or p.get('sov_a3'))
    if len(a3) != 3:
        continue
    name_en = str(p.get('name_en') or p.get('name') or '').strip()
    if not name_en:
        continue
    code = clean_code(p.get('iso_3166_2') or p.get('adm1_code') or f'{a3}-{len(admin_by_country.get(a3, []))+1}')
    lat = p.get('latitude'); lng = p.get('longitude')
    try: lat = float(lat)
    except Exception: lat = None
    try: lng = float(lng)
    except Exception: lng = None
    terrain, climate = terrain_and_climate(a3, name_en, lat, lng)
    item = {
        'code': code,
        'nameEn': name_en,
        'nameAr': str(p.get('name_ar') or name_en).strip(),
        'lat': lat,
        'lng': lng,
        'terrain': terrain,
        'climate': climate,
    }
    admin_by_country.setdefault(a3, []).append(item)
    rings = geometry_rings(f.get('geometry') or {})
    if rings:
        shape_countries.setdefault(a3, []).append({**item, 'rings': rings})

# Deduplicate administrative units by code/name while preserving Natural Earth order.
for a3, xs in list(admin_by_country.items()):
    seen = set(); clean = []
    for x in xs:
        key = x['code'] or x['nameEn'].casefold()
        if key in seen:
            continue
        seen.add(key); clean.append(x)
    admin_by_country[a3] = clean
for a3, xs in list(shape_countries.items()):
    seen = set(); clean = []
    for x in xs:
        key = x['code'] or x['nameEn'].casefold()
        if key in seen:
            continue
        seen.add(key); clean.append(x)
    shape_countries[a3] = clean

out = []
for c in countries:
    if c.get('independent') is not True:
        continue
    a2 = str(c.get('cca2', '')).upper(); a3 = str(c.get('cca3', '')).upper()
    if len(a2) != 2 or len(a3) != 3:
        continue
    trans = c.get('translations') or {}; ar = (trans.get('ara') or {}).get('common')
    latlng = c.get('latlng') or [0, 0]
    out.append({
        'iso2': a2, 'iso3': a3,
        'nameEn': (c.get('name') or {}).get('common', a3),
        'nameAr': ar or (c.get('name') or {}).get('common', a3),
        'capital': ((c.get('capital') or ['Capital'])[0]),
        'population': int(c.get('population') or 1_000_000),
        'lat': float(latlng[0] if len(latlng) > 0 else 0),
        'lng': float(latlng[1] if len(latlng) > 1 else 0),
        'landlocked': bool(c.get('landlocked')),
        'borders': [str(x).upper() for x in (c.get('borders') or []) if len(str(x)) == 3],
        'regions': admin_by_country.get(a3, []),
    })
out.sort(key=lambda x: x['iso3'])

world_text = json.dumps(out, ensure_ascii=False, separators=(',', ':'))
shape_payload = {'version': 1, 'source': 'Natural Earth Admin-1', 'countries': shape_countries}
shape_text = json.dumps(shape_payload, ensure_ascii=False, separators=(',', ':'))
(ROOT/'assets').mkdir(exist_ok=True)
(ROOT/'assets/world_game_data.json').write_text(world_text, encoding='utf-8')
(ROOT/'assets/province_map.json').write_text(shape_text, encoding='utf-8')
(ROOT/'server/world_game_data.json').write_text(world_text, encoding='utf-8')
print(f'world data: {len(out)} countries, {sum(len(x["regions"]) for x in out)} admin-1 units')
print(f'province map: {sum(len(v) for v in shape_countries.values())} polygon features, {len(shape_text)/1_000_000:.1f} MB compact JSON')
