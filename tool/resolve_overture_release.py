#!/usr/bin/env python3
"""Resolve a currently published Overture Transportation PMTiles release.

Overture public release artifacts have a retention window, so release CI must not
hard-code an old monthly release forever. This script reads Overture's official
STAC catalog, probes the newest releases, and exports the live release/URL through
GITHUB_ENV for subsequent build steps.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request

STAC_URL = os.environ.get('WD_OVERTURE_STAC_URL', 'https://stac.overturemaps.org/catalog.json')
BASES = (
    'https://overturemaps-extras-us-west-2.s3.us-west-2.amazonaws.com/tiles',
    'https://overturemaps-extras-us-west-2.s3.amazonaws.com/tiles',
)
TIMEOUT = 20


def fetch_catalog() -> dict:
    req = urllib.request.Request(STAC_URL, headers={'User-Agent': 'World-Dominion-Build/1.8.1'})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
        return json.load(response)


def releases_from_catalog(catalog: dict) -> list[str]:
    out: list[str] = []
    latest = str(catalog.get('latest') or '').strip()
    if latest:
        out.append(latest)
    for link in catalog.get('links') or []:
        if link.get('rel') != 'child':
            continue
        text = f"{link.get('href', '')} {link.get('title', '')}"
        match = re.search(r'(20\d{2}-\d{2}-\d{2}\.\d+)', text)
        if match:
            out.append(match.group(1))
    unique = sorted(set(out), reverse=True)
    if latest in unique:
        unique.remove(latest)
        unique.insert(0, latest)
    return unique[:4]


def probe(url: str) -> tuple[bool, str]:
    req = urllib.request.Request(
        url,
        headers={
            'User-Agent': 'World-Dominion-Build/1.8.1',
            'Accept-Encoding': 'identity',
            'Range': 'bytes=0-126',
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as response:
            data = response.read(127)
            status = getattr(response, 'status', 200)
        if status not in (200, 206):
            return False, f'HTTP {status}'
        if len(data) < 127:
            return False, f'short PMTiles header ({len(data)} bytes)'
        if data[:7] != b'PMTiles':
            return False, 'not a PMTiles v3 archive'
        return True, f'HTTP {status}'
    except urllib.error.HTTPError as exc:
        return False, f'HTTP {exc.code}'
    except Exception as exc:
        return False, f'{type(exc).__name__}: {exc}'


def export_env(release: str, url: str) -> None:
    env_file = os.environ.get('GITHUB_ENV')
    lines = f'WD_OVERTURE_RELEASE={release}\nWD_OVERTURE_PM_URL={url}\n'
    if env_file:
        with open(env_file, 'a', encoding='utf-8') as handle:
            handle.write(lines)
    else:
        print(lines, end='')


def main() -> int:
    catalog = fetch_catalog()
    candidates = releases_from_catalog(catalog)
    print(f"Overture STAC latest: {catalog.get('latest')}")
    print(f"Overture live release candidates: {', '.join(candidates) or 'none'}")
    for release in candidates:
        for base in BASES:
            url = f'{base}/{release}/transportation.pmtiles'
            ok, detail = probe(url)
            print(f'Overture PMTiles preflight {release}: {detail} ({base})')
            if ok:
                export_env(release, url)
                print(f'Selected Overture Transportation release: {release}')
                return 0
    print('No currently published Overture Transportation PMTiles artifact passed preflight', file=sys.stderr)
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
