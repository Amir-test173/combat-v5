#!/usr/bin/env python3
"""Build World Dominion v1.7 physical-world assets.

The game remains fully playable with fallback values, but release CI can require the
real layers. Real build layers are deliberately compressed into province-level
strategic data so APK size and runtime stay practical:

* Copernicus DEM GLO-90: deterministic multi-point elevation samples per Admin-1.
* ESA WorldCover 2021 v200: deterministic multi-point land-cover samples per Admin-1.
* Overture Maps Transportation PMTiles: strategic road hierarchy + rail at z9.

Important: this is NOT a per-pixel terrain simulator and ``actualRoadKm`` means the
strategic road network retained for gameplay (motorway/trunk/primary/secondary), not
all local streets. The manifest records source/coverage/quality explicitly.
"""
from __future__ import annotations

import gzip
import json
import math
import os
import pathlib
import statistics
import urllib.request
import urllib.error
import time
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed

from transport_pipeline import (
    is_strategic_transport,
    safe_bbox_tile_ranges,
    tile_bounds,
    tile_local_to_lonlat,
    transport_priority,
)

ROOT = pathlib.Path(__file__).resolve().parents[1]
WORLD_PATH = ROOT / 'assets' / 'world_game_data.json'
SHAPE_PATH = ROOT / 'assets' / 'province_map.json'
TRANSPORT_PATH = ROOT / 'assets' / 'transport_map.json'
MANIFEST_PATH = ROOT / 'assets' / 'geodata_manifest.json'
SERVER_WORLD_PATH = ROOT / 'server' / 'world_game_data.json'
SERVER_MANIFEST_PATH = ROOT / 'server' / 'geodata_manifest.json'

NE_VERSION = 'v5.1.2'
NE_ROADS = f'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/{NE_VERSION}/geojson/ne_10m_roads.geojson'
WORLD_COVER_BASE = 'https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map'
COP90_BASE = 'https://copernicus-dem-90m.s3.eu-central-1.amazonaws.com'
OVERTURE_RELEASE = os.environ.get('WD_OVERTURE_RELEASE', '2026-06-17.0').strip()
OVERTURE_FALLBACK_RELEASES = tuple(
    x.strip() for x in os.environ.get('WD_OVERTURE_FALLBACK_RELEASES', '2026-05-20.0,2026-04-15.0').split(',') if x.strip()
)
OVERTURE_PM_OVERRIDE = os.environ.get('WD_OVERTURE_PM_URL', '').strip()
OVERTURE_PM_BASE = os.environ.get(
    'WD_OVERTURE_PM_BASE',
    'https://overturemaps-extras-us-west-2.s3.us-west-2.amazonaws.com/tiles',
).rstrip('/')
OVERTURE_PROBE_RETRIES = max(1, min(5, int(os.environ.get('WD_OVERTURE_PROBE_RETRIES', '3') or 3)))
OVERTURE_PROBE_TIMEOUT = max(5, min(60, int(os.environ.get('WD_OVERTURE_PROBE_TIMEOUT', '20') or 20)))
RESOLVED_OVERTURE_PM = None
RESOLVED_OVERTURE_RELEASE = None
TRANSPORT_ZOOM = max(4, min(12, int(os.environ.get('WD_TRANSPORT_ZOOM', '9') or 9)))
TRANSPORT_SOURCE = os.environ.get('WD_TRANSPORT_SOURCE', 'overture').strip().lower()
RASTER_SAMPLES = max(1, min(7, int(os.environ.get('WD_RASTER_SAMPLES', '3') or 3)))
MAX_TRANSPORT_TILES = max(1000, int(os.environ.get('WD_MAX_TRANSPORT_TILES', '140000') or 140000))
MAX_RENDER_PER_PROVINCE = max(4, min(80, int(os.environ.get('WD_MAX_RENDER_LINES_PER_PROVINCE', '22') or 22)))
RANGE_BATCH_BYTES = max(262144, int(os.environ.get('WD_PM_RANGE_BATCH_BYTES', '4194304') or 4194304))
RANGE_GAP_BYTES = max(0, int(os.environ.get('WD_PM_RANGE_GAP_BYTES', '65536') or 65536))
SKIP_REMOTE = os.environ.get('WD_SKIP_REMOTE_PHYSICAL', '').lower() in {'1','true','yes'}
SKIP_RASTER = SKIP_REMOTE or os.environ.get('WD_SKIP_RASTER', '').lower() in {'1','true','yes'}
SKIP_TRANSPORT = SKIP_REMOTE or os.environ.get('WD_SKIP_TRANSPORT', '').lower() in {'1','true','yes'} or TRANSPORT_SOURCE == 'skip'
ROADS_FILE = os.environ.get('WD_ROADS_FILE','').strip()
REQUIRE_REAL = os.environ.get('WD_REQUIRE_REAL_GEO', '').lower() in {'1','true','yes'}
REQUIRE_REAL_TRANSPORT = os.environ.get('WD_REQUIRE_REAL_TRANSPORT', '').lower() in {'1','true','yes'}
GEO_WORKERS = max(1, min(16, int(os.environ.get('WD_GEO_WORKERS','8') or 8)))

LANDCOVER = {
    10: 'tree_cover', 20: 'shrubland', 30: 'grassland', 40: 'cropland',
    50: 'built_up', 60: 'bare_sparse', 70: 'snow_ice', 80: 'water',
    90: 'wetland', 95: 'mangroves', 100: 'moss_lichen',
}
ROAD_CLASSES = ('motorway','trunk','primary','secondary')


def overture_pm_url(release: str) -> str:
    return f'{OVERTURE_PM_BASE}/{release}/transportation.pmtiles'


def probe_pmtiles(url: str) -> tuple[bool, str]:
    """Fast, dependency-free PMTiles availability probe.

    Overture release notes document the public S3 directory, but an individual
    release artifact can occasionally be late or unavailable. Probe the first
    PMTiles header bytes before spending ~15 minutes on global raster enrichment.
    """
    headers={
        'User-Agent':'World-Dominion-Build/1.8.1',
        'Accept-Encoding':'identity',
        'Range':'bytes=0-126',
    }
    last='unknown error'
    for attempt in range(1, OVERTURE_PROBE_RETRIES+1):
        try:
            req=urllib.request.Request(url,headers=headers)
            with urllib.request.urlopen(req,timeout=OVERTURE_PROBE_TIMEOUT) as r:
                data=r.read(127)
                status=getattr(r,'status',200)
                if status not in (200,206):
                    last=f'HTTP {status}'
                elif len(data) < 127:
                    last=f'short header ({len(data)} bytes)'
                elif data[:7] != b'PMTiles':
                    last='response is not a PMTiles v3 archive'
                else:
                    return True, f'HTTP {status}'
        except urllib.error.HTTPError as e:
            last=f'HTTP {e.code}'
            if e.code == 404:
                break
        except Exception as e:
            last=f'{type(e).__name__}: {e}'
        if attempt < OVERTURE_PROBE_RETRIES:
            time.sleep(min(4, attempt))
    return False,last


def resolve_overture_pmtiles() -> tuple[str|None, str|None]:
    """Resolve a real Overture Transportation PMTiles artifact.

    Prefer the pinned release. If that release's optional PMTiles artifact is
    missing, fall back to the nearest explicitly pinned prior Overture release
    rather than silently switching to Natural Earth. The actual release used is
    recorded in geodata_manifest.json.
    """
    global RESOLVED_OVERTURE_PM, RESOLVED_OVERTURE_RELEASE
    if RESOLVED_OVERTURE_PM:
        return RESOLVED_OVERTURE_PM, RESOLVED_OVERTURE_RELEASE
    candidates=[]
    if OVERTURE_PM_OVERRIDE:
        candidates.append(('override',OVERTURE_PM_OVERRIDE))
    else:
        seen=set()
        for release in (OVERTURE_RELEASE,*OVERTURE_FALLBACK_RELEASES):
            if release and release not in seen:
                seen.add(release);candidates.append((release,overture_pm_url(release)))
    for release,url in candidates:
        ok,why=probe_pmtiles(url)
        print(f'Overture PMTiles preflight {release}: {why}')
        if ok:
            RESOLVED_OVERTURE_PM=url
            RESOLVED_OVERTURE_RELEASE=OVERTURE_RELEASE if release=='override' else release
            if RESOLVED_OVERTURE_RELEASE != OVERTURE_RELEASE:
                print(f'warning: requested Overture {OVERTURE_RELEASE} PMTiles unavailable; using real Transportation PMTiles {RESOLVED_OVERTURE_RELEASE}')
            return RESOLVED_OVERTURE_PM,RESOLVED_OVERTURE_RELEASE
    return None,None


def load_json(path: pathlib.Path):
    return json.loads(path.read_text(encoding='utf-8'))


def fetch_json(url: str):
    req = urllib.request.Request(url, headers={'User-Agent':'World-Dominion-Build/1.7'})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.load(r)


def sign_tile(value: int, pos: str, neg: str, width: int):
    return f'{pos if value >= 0 else neg}{abs(value):0{width}d}'


def cop90_url(lat: float, lon: float):
    lat = min(89.999999, max(-89.999999, lat)); lon = min(179.999999, max(-179.999999, lon))
    y, x = math.floor(lat), math.floor(lon)
    north = sign_tile(y, 'N', 'S', 2) + '_00'; east = sign_tile(x, 'E', 'W', 3) + '_00'
    name = f'Copernicus_DSM_COG_30_{north}_{east}_DEM'
    return f'{COP90_BASE}/{name}/{name}.tif'


def worldcover_url(lat: float, lon: float):
    lat = min(89.999999, max(-89.999999, lat)); lon = min(179.999999, max(-179.999999, lon))
    y, x = math.floor(lat/3)*3, math.floor(lon/3)*3
    tile = sign_tile(y, 'N', 'S', 2) + sign_tile(x, 'E', 'W', 3)
    return f'{WORLD_COVER_BASE}/ESA_WorldCover_10m_2021_v200_{tile}_Map.tif'


def terrain_from_real(region):
    cover = str(region.get('landCover') or '')
    elevation = float(region.get('elevationM') or 0); relief = float(region.get('reliefM') or 0)
    climate = str(region.get('climate') or 'temperate')
    if cover == 'built_up': return 'urban'
    if cover == 'snow_ice' or climate == 'arctic': return 'arctic'
    if relief >= 520 or (elevation >= 1500 and relief >= 180): return 'mountains'
    if relief >= 210 or elevation >= 900: return 'hills'
    if cover in {'tree_cover','mangroves'}: return 'jungle' if climate == 'tropical' else 'forest'
    if cover in {'bare_sparse','shrubland'} and climate == 'arid': return 'desert'
    if cover == 'moss_lichen' and abs(float(region.get('lat') or 0)) > 52: return 'arctic'
    return str(region.get('terrain') or 'plains')


def rings_to_geometry(shape_row):
    try:
        from shapely.geometry import Polygon, MultiPolygon
        from shapely.ops import unary_union
    except Exception:
        return None
    polys=[]
    for ring in shape_row.get('rings') or []:
        if len(ring) >= 4:
            try:
                p=Polygon(ring)
                if not p.is_valid: p=p.buffer(0)
                if not p.is_empty: polys.append(p)
            except Exception: pass
    if not polys: return None
    try:
        merged=unary_union(polys)
        return merged if not merged.is_empty else None
    except Exception:
        return polys[0] if len(polys)==1 else MultiPolygon(polys)


def geometry_lines(g):
    if g is None or g.is_empty: return []
    if g.geom_type == 'LineString': return [g]
    if g.geom_type == 'MultiLineString': return list(g.geoms)
    if g.geom_type == 'GeometryCollection':
        out=[]
        for x in g.geoms: out.extend(geometry_lines(x))
        return out
    return []


def simplify_coords(coords, max_points=90):
    pts=[[round(float(x),4),round(float(y),4)] for x,y,*_ in coords]
    if len(pts)<=max_points:return pts
    step=max(1, math.ceil((len(pts)-1)/(max_points-1)))
    return pts[:-1:step]+[pts[-1]]


def build_province_index(world, shape_payload):
    """Return province rows with real simplified Admin-1 geometry and compute area."""
    try:
        from pyproj import Geod
    except Exception:
        return []
    region_by_key={(c['iso3'],str(r.get('code') or '')):r for c in world for r in (c.get('regions') or [])}
    geod=Geod(ellps='WGS84'); rows=[]
    for country, shapes in (shape_payload.get('countries') or {}).items():
        for shape_row in shapes:
            region=region_by_key.get((country,str(shape_row.get('code') or '')))
            if region is None: continue
            geom=rings_to_geometry(shape_row)
            if geom is None: continue
            try: region['areaSqKm']=round(abs(geod.geometry_area_perimeter(geom)[0])/1_000_000,1)
            except Exception: pass
            rows.append({'country':country,'shape':shape_row,'region':region,'geom':geom})
    return rows


def deterministic_sample_points(province_rows):
    """Pick repeatable interior sample points from the Admin-1 polygon.

    Representative point + centroid + a small interior grid gives significantly more
    spatial coverage than the v1.6/v1.7-centroid prototype while keeping build cost
    bounded. Sampling still summarizes real rasters; it is not a full-pixel survey.
    """
    out={}
    for item in province_rows:
        g=item['geom']; r=item['region']; points=[]
        try:
            rp=g.representative_point(); points.append((float(rp.y),float(rp.x)))
            c=g.centroid
            if g.contains(c): points.append((float(c.y),float(c.x)))
            minx,miny,maxx,maxy=g.bounds
            # deterministic 5x5 candidate lattice ordered around the center
            candidates=[]
            for iy in range(1,5):
                for ix in range(1,5):
                    x=minx+(maxx-minx)*ix/5; y=miny+(maxy-miny)*iy/5
                    candidates.append((abs(ix-2.5)+abs(iy-2.5),x,y))
            from shapely.geometry import Point
            for _,x,y in sorted(candidates):
                p=Point(x,y)
                if g.contains(p): points.append((y,x))
                if len(points)>=RASTER_SAMPLES: break
        except Exception: pass
        # fallback to existing representative location
        if not points:
            try: points=[(float(r.get('lat') or 0),float(r.get('lng') or 0))]
            except Exception: points=[]
        unique=[]; seen=set()
        for lat,lon in points:
            key=(round(lat,5),round(lon,5))
            if key not in seen and -89.9<lat<89.9 and -179.9<lon<179.9:
                seen.add(key);unique.append((lat,lon))
            if len(unique)>=RASTER_SAMPLES: break
        out[(item['country'],str(r.get('code') or ''))]=unique
    return out


def sample_rasters(world, province_rows):
    if SKIP_RASTER: return 0,0,0,0
    try:
        import numpy as np
        import rasterio
        from rasterio.windows import Window
    except Exception as e:
        print(f'physical raster enrichment unavailable: {e}'); return 0,0,0,0

    samples=deterministic_sample_points(province_rows)
    region_by_key={(c['iso3'],str(r.get('code') or '')):r for c in world for r in (c.get('regions') or [])}
    elev_groups,cover_groups=defaultdict(list),defaultdict(list)
    for key,pts in samples.items():
        for sample_i,(lat,lon) in enumerate(pts):
            elev_groups[cop90_url(lat,lon)].append((key,sample_i,lat,lon))
            cover_groups[worldcover_url(lat,lon)].append((key,sample_i,lat,lon))

    env=dict(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif',GDAL_HTTP_MAX_RETRY='2',GDAL_HTTP_RETRY_DELAY='1',GDAL_HTTP_CONNECTTIMEOUT='15',GDAL_HTTP_TIMEOUT='60',VSI_CACHE='TRUE',VSI_CACHE_SIZE='8000000')

    def elevation_tile(job):
        url,items=job; result=[]
        try:
            with rasterio.Env(**env),rasterio.open(url) as src:
                for key,sample_i,lat,lon in items:
                    row,col=src.index(lon,lat);x0,y0=max(0,col-10),max(0,row-10)
                    arr=src.read(1,window=Window(x0,y0,min(21,src.width-x0),min(21,src.height-y0)),masked=True)
                    vals=np.asarray(arr.compressed(),dtype='float64');vals=vals[np.isfinite(vals)]
                    if vals.size: result.append((key,sample_i,float(np.median(vals)),float(np.percentile(vals,5)),float(np.percentile(vals,95))))
        except Exception as e: print(f'warning: DEM tile failed {url.rsplit("/",2)[-2]}: {type(e).__name__}')
        return result

    def cover_tile(job):
        url,items=job; result=[]
        try:
            with rasterio.Env(**env),rasterio.open(url) as src:
                for key,sample_i,lat,lon in items:
                    row,col=src.index(lon,lat);x0,y0=max(0,col-55),max(0,row-55)
                    arr=src.read(1,window=Window(x0,y0,min(111,src.width-x0),min(111,src.height-y0)),masked=True)
                    vals=np.asarray(arr.compressed(),dtype='int32');vals=vals[vals>0]
                    if vals.size:
                        codes,counts=np.unique(vals,return_counts=True)
                        result.append((key,sample_i,{int(c):int(n) for c,n in zip(codes,counts)}))
        except Exception as e: print(f'warning: WorldCover tile failed {url.rsplit("/",1)[-1]}: {type(e).__name__}')
        return result

    def run_grouped(groups,fn,label):
        output=[];jobs=list(groups.items());print(f'{label}: {len(jobs)} remote COG groups, workers={GEO_WORKERS}')
        with ThreadPoolExecutor(max_workers=GEO_WORKERS) as pool:
            fs=[pool.submit(fn,j) for j in jobs]
            for i,f in enumerate(as_completed(fs),1):
                try: output.extend(f.result() or [])
                except Exception as e: print(f'warning: {label} worker failed: {type(e).__name__}')
                if i%100==0 or i==len(fs):print(f'{label}: {i}/{len(fs)} groups')
        return output

    elev_rows=run_grouped(elev_groups,elevation_tile,'DEM');cover_rows=run_grouped(cover_groups,cover_tile,'WorldCover')
    elev_by=defaultdict(list);cover_by=defaultdict(list)
    for key,_,med,lo,hi in elev_rows:elev_by[key].append((med,lo,hi))
    for key,_,counts in cover_rows:cover_by[key].append(counts)
    elev_ok=cover_ok=elev_samples=cover_samples=0
    for key,r in region_by_key.items():
        er=elev_by.get(key,[]);cr=cover_by.get(key,[])
        if er:
            meds=[x[0] for x in er]; lows=[x[1] for x in er]; highs=[x[2] for x in er]
            r['elevationM']=round(float(statistics.median(meds)),1)
            r['elevationMinM']=round(float(min(lows)),1);r['elevationMaxM']=round(float(max(highs)),1)
            r['reliefM']=round(float(max(highs)-min(lows)),1);r['elevationSamples']=len(er);r['elevationReal']=True
            elev_ok+=1;elev_samples+=len(er)
        if cr:
            total_counts=Counter()
            for counts in cr:total_counts.update(counts)
            total=sum(total_counts.values());mix={}
            for code,count in total_counts.most_common(5):mix[LANDCOVER.get(code,f'class_{code}')]=round(count*100/total,1)
            dominant=total_counts.most_common(1)[0][0]
            r['landCover']=LANDCOVER.get(dominant,f'class_{dominant}');r['landCoverMix']=mix;r['landCoverSamples']=len(cr);r['landCoverReal']=True
            cover_ok+=1;cover_samples+=len(cr)
        r['terrain']=terrain_from_real(r)
        both=r.get('elevationReal') and r.get('landCoverReal')
        multi=min(int(r.get('elevationSamples') or 0),int(r.get('landCoverSamples') or 0))>=2
        r['physicalDataQuality']='real_multi' if both and multi else ('real' if both else ('partial' if r.get('elevationReal') or r.get('landCoverReal') else 'fallback'))
    return elev_ok,cover_ok,elev_samples,cover_samples


class HTTPRangeSource:
    """Synchronous HTTP Range source with bounded retries for public PMTiles."""
    def __init__(self,url):
        import requests
        self.url=url;self.session=requests.Session();self.cache={}
        self.headers={'User-Agent':'World-Dominion-Build/1.8.1','Accept-Encoding':'identity'}
    def _get(self,start,length,timeout):
        last=None
        for attempt in range(1,4):
            try:
                r=self.session.get(self.url,headers={**self.headers,'Range':f'bytes={start}-{start+length-1}'},timeout=timeout)
                if r.status_code in (200,206):
                    data=r.content
                    if r.status_code==200 and len(data)>length:data=data[start:start+length]
                    if len(data)==length:return data
                    last=RuntimeError(f'PMTiles short range {len(data)} != {length}')
                elif r.status_code==404:
                    raise RuntimeError(f'PMTiles HTTP 404 for {self.url}')
                else:
                    last=RuntimeError(f'PMTiles HTTP {r.status_code}')
            except Exception as e:
                last=e
                if '404' in str(e):raise
            if attempt<3:time.sleep(attempt)
        raise last or RuntimeError('PMTiles range request failed')
    def __call__(self,offset,length):
        key=(int(offset),int(length))
        if key in self.cache:return self.cache[key]
        data=self._get(key[0],key[1],90)
        if key[1] <= 512000:self.cache[key]=data
        return data
    def batch(self,start,length):
        return self._get(int(start),int(length),120)


def decompress_tile(data,compression):
    name=str(getattr(compression,'name',compression)).upper()
    if name in {'NONE','1'}:return data
    if name in {'GZIP','2'}:return gzip.decompress(data)
    if name in {'ZSTD','4'}:
        import zstandard as zstd
        return zstd.ZstdDecompressor().decompress(data)
    raise RuntimeError(f'unsupported PMTiles tile compression {compression}')


def tile_entries_for_ids(source,tile_ids):
    """Resolve selected PMTiles IDs to payload ranges with directory caching."""
    from pmtiles.tile import deserialize_header,deserialize_directory,find_tile
    header=deserialize_header(source(0,127));dirs={}
    def directory(off,length):
        key=(off,length)
        if key not in dirs:dirs[key]=deserialize_directory(source(off,length))
        return dirs[key]
    out={}
    for tile_id in sorted(tile_ids):
        off=header['root_offset'];length=header['root_length']
        for _ in range(4):
            entry=find_tile(directory(off,length),tile_id)
            if not entry:break
            if entry.run_length==0:
                off=header['leaf_directory_offset']+entry.offset;length=entry.length;continue
            if tile_id-entry.tile_id < entry.run_length:
                out[tile_id]=(header['tile_data_offset']+entry.offset,entry.length);break
            break
    return header,out


def strategic_tile_ids(province_rows,zoom):
    """Select only z/x/y tiles intersecting land Admin-1 polygons."""
    from shapely.geometry import box
    from pmtiles.tile import zxy_to_tileid
    selected={}
    for item in province_rows:
        geom=item['geom']
        for x0,x1,y0,y1 in safe_bbox_tile_ranges(geom.bounds,zoom):
            for x in range(x0,x1+1):
                for y in range(y0,y1+1):
                    key=(x,y)
                    if key in selected:continue
                    west,south,east,north=tile_bounds(zoom,x,y)
                    try:
                        if geom.intersects(box(west,south,east,north)):selected[key]=zxy_to_tileid(zoom,x,y)
                    except Exception:pass
                    if len(selected)>MAX_TRANSPORT_TILES:raise RuntimeError(f'strategic tile safety limit exceeded ({MAX_TRANSPORT_TILES})')
    return selected


def enrich_transport_overture(world,province_rows):
    """Read a global strategic road/rail network from Overture PMTiles by HTTP ranges."""
    import mapbox_vector_tile
    from pyproj import Geod
    from shapely.geometry import LineString,MultiLineString,box
    from shapely.strtree import STRtree
    from pmtiles.tile import Compression

    selected=strategic_tile_ids(province_rows,TRANSPORT_ZOOM)
    if not selected:raise RuntimeError('no strategic Overture tiles intersect Admin-1 geometries')
    print(f'Overture transportation: selected {len(selected)} z{TRANSPORT_ZOOM} land tiles')
    url,release=resolve_overture_pmtiles()
    if not url:raise RuntimeError('no real Overture Transportation PMTiles release passed preflight')
    source=HTTPRangeSource(url)
    header,entries=tile_entries_for_ids(source,set(selected.values()))
    if not entries:raise RuntimeError('Overture PMTiles returned no selected tile entries')
    id_to_xy={tid:xy for xy,tid in selected.items()}
    rows=sorted((off,length,tid) for tid,(off,length) in entries.items() if tid in id_to_xy)
    geoms=[x['geom'] for x in province_rows];tree=STRtree(geoms);geom_idx={id(g):i for i,g in enumerate(geoms)}
    geod=Geod(ellps='WGS84');road_km=defaultdict(lambda:defaultdict(float));rail_km=defaultdict(lambda:defaultdict(float));render=defaultdict(list)
    tile_count=feature_count=0

    # Merge nearby clustered PMTiles payloads to avoid one network round-trip per tile.
    batches=[];cur=[];start=end=None
    for off,length,tid in rows:
        if start is None:start=off;end=off+length;cur=[(off,length,tid)]
        elif off-end<=RANGE_GAP_BYTES and off+length-start<=RANGE_BATCH_BYTES:
            cur.append((off,length,tid));end=max(end,off+length)
        else:
            batches.append((start,end-start,cur));start=off;end=off+length;cur=[(off,length,tid)]
    if cur:batches.append((start,end-start,cur))
    print(f'Overture transportation: {len(rows)} tile payloads in {len(batches)} HTTP range batches')

    for bi,(batch_start,batch_len,items) in enumerate(batches,1):
        blob=source.batch(batch_start,batch_len)
        for off,length,tid in items:
            raw=blob[off-batch_start:off-batch_start+length]
            try: pbf=decompress_tile(raw,header['tile_compression']);decoded=mapbox_vector_tile.decode(pbf,default_options={'y_coord_down':True})
            except Exception as e:
                print(f'warning: vector tile decode failed: {type(e).__name__}');continue
            layer=decoded.get('segment') or decoded.get('transportation') or next((v for k,v in decoded.items() if isinstance(v,dict) and v.get('features')),None)
            if not layer:continue
            extent=float(layer.get('extent') or 4096);x,y=id_to_xy[tid];west,south,east,north=tile_bounds(TRANSPORT_ZOOM,x,y);tile_poly=box(west,south,east,north)
            for feat in layer.get('features') or []:
                props=feat.get('properties') or {};subtype=str(props.get('subtype') or '').lower();clazz=str(props.get('class') or '').lower()
                if not is_strategic_transport(subtype,clazz):continue
                gj=feat.get('geometry') or {};typ=gj.get('type');coords=gj.get('coordinates')
                raw_lines=coords if typ=='MultiLineString' else [coords] if typ=='LineString' else []
                for raw_line in raw_lines:
                    if not raw_line or len(raw_line)<2:continue
                    pts=[tile_local_to_lonlat(TRANSPORT_ZOOM,x,y,p[0],p[1],extent,y_down=True) for p in raw_line]
                    try:
                        line=LineString(pts).intersection(tile_poly)
                    except Exception:continue
                    for segment in geometry_lines(line):
                        if segment.is_empty or len(segment.coords)<2:continue
                        try:candidates=tree.query(segment)
                        except Exception:candidates=[]
                        idxs=[]
                        for q in candidates:
                            if isinstance(q,(int,)) or type(q).__name__.startswith('int'):idxs.append(int(q))
                            else:
                                i=geom_idx.get(id(q))
                                if i is not None:idxs.append(i)
                        for idx in idxs:
                            item=province_rows[idx];poly=item['geom']
                            try: clipped=segment.intersection(poly)
                            except Exception:continue
                            for piece in geometry_lines(clipped):
                                if piece.is_empty or len(piece.coords)<2:continue
                                try:km=abs(float(geod.geometry_length(piece)))/1000
                                except Exception:continue
                                if km<=.005:continue
                                r=item['region'];key=(item['country'],str(r.get('code') or ''))
                                if subtype=='rail':rail_km[key][clazz or 'rail']+=km
                                else:road_km[key][clazz]+=km
                                simp=piece.simplify(.008 if clazz in {'motorway','trunk'} else .012,preserve_topology=False)
                                for sl in geometry_lines(simp):
                                    outpts=simplify_coords(list(sl.coords),70)
                                    if len(outpts)>=2:render[key].append((transport_priority(subtype,clazz,km),{'kind':subtype,'class':clazz or subtype,'provinceCode':r.get('code'),'points':outpts}))
                                feature_count+=1
            tile_count+=1
        if bi%100==0 or bi==len(batches):print(f'Overture transportation: {bi}/{len(batches)} batches')

    country_lines=defaultdict(list)
    real_regions=0;total_road=total_rail=0.0
    for item in province_rows:
        r=item['region'];key=(item['country'],str(r.get('code') or ''));rc=dict(road_km.get(key,{}));rr=dict(rail_km.get(key,{}))
        for cls in ROAD_CLASSES:rc.setdefault(cls,0.0)
        r['roadClassKm']={k:round(v,1) for k,v in rc.items()};r['railClassKm']={k:round(v,1) for k,v in rr.items()}
        r['actualRoadKm']=round(sum(rc.values()),1);r['actualRailKm']=round(sum(rr.values()),1)
        area=max(10.0,float(r.get('areaSqKm') or 0) or 1000.0)
        r['roadDensity']=round(r['actualRoadKm']/area*1000,2);r['railDensity']=round(r['actualRailKm']/area*1000,2)
        r['transportDataQuality']=f'overture_strategic_z{TRANSPORT_ZOOM}';real_regions+=1;total_road+=r['actualRoadKm'];total_rail+=r['actualRailKm']
        for _,line in sorted(render.get(key,[]),key=lambda x:x[0],reverse=True)[:MAX_RENDER_PER_PROVINCE]:country_lines[item['country']].append(line)
    payload={'version':3,'source':'Overture Maps Transportation','release':release,'zoom':TRANSPORT_ZOOM,'network':'motorway+trunk+primary+secondary+rail','countries':dict(country_lines)}
    TRANSPORT_PATH.write_text(json.dumps(payload,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    return {'real':True,'source':'overture','regions':real_regions,'tiles':tile_count,'features':feature_count,'renderLines':sum(len(v) for v in country_lines.values()),'roadKm':round(total_road,1),'railKm':round(total_rail,1)}


def enrich_transport_natural_earth(world,province_rows):
    """Small fallback only; never presented as the complete global road network."""
    from shapely.geometry import shape as geo_shape
    from pyproj import Geod
    geod=Geod(ellps='WGS84');region_rows=province_rows
    roads=json.loads(pathlib.Path(ROADS_FILE).read_text(encoding='utf-8')) if ROADS_FILE else fetch_json(NE_ROADS)
    render=defaultdict(list);hits=0
    for feat in roads.get('features') or []:
        props=feat.get('properties') or {}
        try:rank=float(props.get('scalerank') if props.get('scalerank') is not None else 5)
        except Exception:rank=5
        if rank>7:continue
        try:g=geo_shape(feat.get('geometry'))
        except Exception:continue
        for item in region_rows:
            if not g.intersects(item['geom']):continue
            try:clipped=g.intersection(item['geom'])
            except Exception:continue
            km=0
            for line in geometry_lines(clipped):
                try:km+=abs(float(geod.geometry_length(line)))/1000
                except Exception:pass
                pts=simplify_coords(list(line.simplify(.025,preserve_topology=False).coords),70) if line.geom_type=='LineString' else []
                if len(pts)>=2:render[item['country']].append({'kind':'road','class':'fallback_major','provinceCode':item['region'].get('code'),'points':pts})
            if km>0:item['region']['actualRoadKm']=round(float(item['region'].get('actualRoadKm') or 0)+km,1);hits+=1
    for item in region_rows:
        r=item['region'];area=max(10.0,float(r.get('areaSqKm') or 0) or 1000.0);r['roadDensity']=round(float(r.get('actualRoadKm') or 0)/area*1000,2);r['transportDataQuality']='natural_earth_fallback';r.setdefault('roadClassKm',{});r.setdefault('railClassKm',{})
    TRANSPORT_PATH.write_text(json.dumps({'version':3,'source':f'Natural Earth {NE_VERSION} fallback','countries':dict(render)},ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    return {'real':False,'source':'natural_earth_fallback','regions':0,'tiles':0,'features':hits,'renderLines':sum(len(v) for v in render.values()),'roadKm':round(sum(float(x['region'].get('actualRoadKm') or 0) for x in region_rows),1),'railKm':0.0}


def enrich_transport(world,province_rows):
    empty={'version':3,'source':'fallback/none','countries':{}}
    if SKIP_TRANSPORT:
        TRANSPORT_PATH.write_text(json.dumps(empty,separators=(',',':')),encoding='utf-8');return {'real':False,'source':'skipped','regions':0,'tiles':0,'features':0,'renderLines':0,'roadKm':0,'railKm':0}
    if TRANSPORT_SOURCE=='natural-earth':return enrich_transport_natural_earth(world,province_rows)
    try:return enrich_transport_overture(world,province_rows)
    except Exception as e:
        print(f'warning: Overture strategic transport failed: {type(e).__name__}: {e}')
        try:return enrich_transport_natural_earth(world,province_rows)
        except Exception as f:
            print(f'warning: Natural Earth transport fallback also failed: {type(f).__name__}: {f}')
            TRANSPORT_PATH.write_text(json.dumps(empty,separators=(',',':')),encoding='utf-8');return {'real':False,'source':'failed','regions':0,'tiles':0,'features':0,'renderLines':0,'roadKm':0,'railKm':0}


def main():
    world=load_json(WORLD_PATH);shapes=load_json(SHAPE_PATH);total_regions=0
    for c in world:
        for r in c.get('regions') or []:
            total_regions+=1
            r.setdefault('elevationM',0.0);r.setdefault('elevationMinM',r.get('elevationM',0.0));r.setdefault('elevationMaxM',r.get('elevationM',0.0));r.setdefault('elevationSamples',0);r.setdefault('reliefM',0.0)
            r.setdefault('landCover','unknown');r.setdefault('landCoverMix',{});r.setdefault('landCoverSamples',0)
            r.setdefault('actualRoadKm',0.0);r.setdefault('actualRailKm',0.0);r.setdefault('roadDensity',0.0);r.setdefault('railDensity',0.0);r.setdefault('roadClassKm',{});r.setdefault('railClassKm',{})
            r.setdefault('physicalDataQuality','fallback');r.setdefault('transportDataQuality','fallback')
    province_rows=build_province_index(world,shapes)
    # Resolve transport first: a missing optional PMTiles artifact must fail/fallback
    # in seconds, not after global DEM/WorldCover sampling has already run.
    if not SKIP_TRANSPORT and TRANSPORT_SOURCE=='overture':
        url,release=resolve_overture_pmtiles()
        if os.environ.get('WD_PROBE_TRANSPORT_ONLY','').lower() in {'1','true','yes'}:
            if not url:raise SystemExit('No real Overture Transportation PMTiles artifact passed preflight')
            print(json.dumps({'transportUrl':url,'transportRelease':release},ensure_ascii=False))
            return
        if REQUIRE_REAL_TRANSPORT and not url:
            raise SystemExit('WD_REQUIRE_REAL_TRANSPORT=1 but no real Overture Transportation PMTiles artifact passed preflight')
    elev_ok,cover_ok,elev_samples,cover_samples=sample_rasters(world,province_rows)
    transport=enrich_transport(world,province_rows)
    WORLD_PATH.write_text(json.dumps(world,ensure_ascii=False,separators=(',',':')),encoding='utf-8');SERVER_WORLD_PATH.write_text(WORLD_PATH.read_text(encoding='utf-8'),encoding='utf-8')
    manifest={
        'version':2,'regions':total_regions,'provinceGeometryRows':len(province_rows),
        'elevationReal':elev_ok,'landCoverReal':cover_ok,'elevationSamples':elev_samples,'landCoverSamples':cover_samples,'rasterSamplesTarget':RASTER_SAMPLES,
        'elevationSource':'Copernicus DEM GLO-90 (90 m DSM)','landCoverSource':'ESA WorldCover 2021 v200 (10 m)',
        'transportSource':transport['source'],'transportRelease':RESOLVED_OVERTURE_RELEASE if transport['source']=='overture' else None,'transportZoom':TRANSPORT_ZOOM if transport['source']=='overture' else None,
        'transportRealRegions':transport['regions'],'transportTiles':transport['tiles'],'transportFeatures':transport['features'],'transportLines':transport['renderLines'],'strategicRoadKm':transport['roadKm'],'strategicRailKm':transport['railKm'],
        'transportNetworkDefinition':'motorway + trunk + primary + secondary + rail; local/residential streets are intentionally excluded from the mobile strategic layer',
        'samplingNote':'Elevation and land cover aggregate deterministic multi-point samples inside each Admin-1 polygon. They use real rasters but are not a full per-pixel province survey.',
        'remoteSkipped':SKIP_REMOTE,'rasterSkipped':SKIP_RASTER,'transportSkipped':SKIP_TRANSPORT,
    }
    text=json.dumps(manifest,ensure_ascii=False,indent=2);MANIFEST_PATH.write_text(text,encoding='utf-8');SERVER_MANIFEST_PATH.write_text(text,encoding='utf-8');print(json.dumps(manifest,ensure_ascii=False))
    if REQUIRE_REAL and total_regions and (elev_ok/total_regions<.60 or cover_ok/total_regions<.60):raise SystemExit('WD_REQUIRE_REAL_GEO=1 but raster coverage was below 60%')
    if REQUIRE_REAL_TRANSPORT and not transport['real']:raise SystemExit('WD_REQUIRE_REAL_TRANSPORT=1 but Overture strategic transport was not generated')

if __name__=='__main__':main()
