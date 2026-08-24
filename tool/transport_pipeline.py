#!/usr/bin/env python3
"""Small, dependency-light helpers for the v1.7 physical transport build.

The heavy Overture/PMTiles decoder lives in fetch_physical_world.py so the normal
project does not require GIS packages at runtime. These helpers are intentionally
pure so they can be unit-tested on GitHub before remote data is downloaded.
"""
from __future__ import annotations

import math
from typing import Iterable

STRATEGIC_ROAD_CLASSES = {
    "motorway": 5.0,
    "trunk": 4.2,
    "primary": 3.4,
    "secondary": 2.4,
}


def clamp_lat(lat: float) -> float:
    return max(-85.05112878, min(85.05112878, float(lat)))


def lonlat_to_tile(lon: float, lat: float, zoom: int) -> tuple[int, int]:
    """Return XYZ tile coordinates for WGS84 lon/lat."""
    z = max(0, int(zoom)); n = 1 << z
    lon = max(-180.0, min(179.999999999, float(lon)))
    lat = clamp_lat(lat)
    x = int((lon + 180.0) / 360.0 * n)
    lat_rad = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return max(0, min(n - 1, x)), max(0, min(n - 1, y))


def tile_bounds(zoom: int, x: int, y: int) -> tuple[float, float, float, float]:
    """Return (west, south, east, north) for an XYZ tile."""
    n = float(1 << int(zoom))
    west = float(x) / n * 360.0 - 180.0
    east = float(x + 1) / n * 360.0 - 180.0

    def lat_for(row: int) -> float:
        yy = math.pi * (1.0 - 2.0 * float(row) / n)
        return math.degrees(math.atan(math.sinh(yy)))

    north = lat_for(y); south = lat_for(y + 1)
    return west, south, east, north


def tile_local_to_lonlat(
    zoom: int,
    tile_x: int,
    tile_y: int,
    local_x: float,
    local_y: float,
    extent: float = 4096.0,
    *,
    y_down: bool = True,
) -> tuple[float, float]:
    """Convert MVT tile-local coordinates to WGS84.

    mapbox-vector-tile can decode with y_coord_down=True. That coordinate system
    has (0,0) at the tile's upper-left corner, which is the default used here.
    """
    n = float(1 << int(zoom)); extent = max(1.0, float(extent))
    nx = (float(tile_x) + float(local_x) / extent) / n
    ly = float(local_y) if y_down else extent - float(local_y)
    ny = (float(tile_y) + ly / extent) / n
    lon = nx * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * ny))))
    return lon, lat


def is_strategic_transport(subtype: str, road_class: str | None = None) -> bool:
    subtype = str(subtype or "").lower()
    if subtype == "rail":
        return True
    return subtype == "road" and str(road_class or "").lower() in STRATEGIC_ROAD_CLASSES


def transport_priority(subtype: str, road_class: str | None, length_km: float) -> float:
    """Priority for keeping a geometry in the mobile rendering asset.

    All decoded strategic segments still contribute to density statistics. This
    priority only controls which simplified lines are retained for drawing.
    """
    length = max(0.0, float(length_km))
    if str(subtype or "").lower() == "rail":
        return length * 4.7
    return length * STRATEGIC_ROAD_CLASSES.get(str(road_class or "").lower(), 1.0)


def safe_bbox_tile_ranges(bounds: Iterable[float], zoom: int) -> list[tuple[int, int, int, int]]:
    """Convert a normal WGS84 bbox to one or two XYZ tile ranges.

    A bbox wider than 180° is treated as an antimeridian-crossing geometry and
    split near the dateline. This avoids accidentally selecting almost the whole
    planet for Alaska/Russian/Fijian rings.
    """
    west, south, east, north = [float(v) for v in bounds]
    south, north = min(south, north), max(south, north)
    if east - west <= 180.0:
        x0, y1 = lonlat_to_tile(west, south, zoom)
        x1, y0 = lonlat_to_tile(east, north, zoom)
        return [(min(x0, x1), max(x0, x1), min(y0, y1), max(y0, y1))]
    # Bounding boxes from dateline-crossing polygons often appear as -179..+179.
    a0, ay1 = lonlat_to_tile(-180.0, south, zoom)
    a1, ay0 = lonlat_to_tile(west, north, zoom)
    b0, by1 = lonlat_to_tile(east, south, zoom)
    b1, by0 = lonlat_to_tile(179.999999, north, zoom)
    return [
        (min(a0, a1), max(a0, a1), min(ay0, ay1), max(ay0, ay1)),
        (min(b0, b1), max(b0, b1), min(by0, by1), max(by0, by1)),
    ]
