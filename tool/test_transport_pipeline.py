import math
import unittest
from unittest.mock import patch

import fetch_physical_world as physical

from transport_pipeline import (
    is_strategic_transport,
    lonlat_to_tile,
    safe_bbox_tile_ranges,
    tile_bounds,
    tile_local_to_lonlat,
    transport_priority,
)


class TransportPipelineTests(unittest.TestCase):
    def test_tile_round_trip_center(self):
        z = 7
        x, y = lonlat_to_tile(2.3522, 48.8566, z)
        west, south, east, north = tile_bounds(z, x, y)
        self.assertLessEqual(west, 2.3522)
        self.assertGreaterEqual(east, 2.3522)
        self.assertLessEqual(south, 48.8566)
        self.assertGreaterEqual(north, 48.8566)
        lon, lat = tile_local_to_lonlat(z, x, y, 2048, 2048, 4096, y_down=True)
        self.assertTrue(math.isfinite(lon) and math.isfinite(lat))
        self.assertGreaterEqual(lon, west)
        self.assertLessEqual(lon, east)
        self.assertGreaterEqual(lat, south)
        self.assertLessEqual(lat, north)

    def test_strategic_filter_keeps_real_network_hierarchy(self):
        for cls in ('motorway', 'trunk', 'primary', 'secondary'):
            self.assertTrue(is_strategic_transport('road', cls))
        self.assertFalse(is_strategic_transport('road', 'residential'))
        self.assertFalse(is_strategic_transport('road', 'footway'))
        self.assertTrue(is_strategic_transport('rail', 'rail'))

    def test_render_priority_preserves_rail_and_highways(self):
        self.assertGreater(transport_priority('rail', 'rail', 10), transport_priority('road', 'secondary', 10))
        self.assertGreater(transport_priority('road', 'motorway', 10), transport_priority('road', 'secondary', 10))

    def test_dateline_bbox_does_not_become_single_worldwide_range(self):
        ranges = safe_bbox_tile_ranges((-179, -10, 179, 10), 6)
        self.assertEqual(len(ranges), 2)
        covered = sum((x1-x0+1)*(y1-y0+1) for x0,x1,y0,y1 in ranges)
        self.assertLess(covered, 200)

    def test_overture_pmtiles_url_is_canonical(self):
        self.assertEqual(
            physical.overture_pm_url('2026-05-20.0'),
            'https://overturemaps-extras-us-west-2.s3.us-west-2.amazonaws.com/tiles/2026-05-20.0/transportation.pmtiles',
        )

    def test_overture_resolver_falls_back_to_previous_real_release(self):
        old_url=physical.RESOLVED_OVERTURE_PM
        old_release=physical.RESOLVED_OVERTURE_RELEASE
        old_override=physical.OVERTURE_PM_OVERRIDE
        old_requested=physical.OVERTURE_RELEASE
        old_fallbacks=physical.OVERTURE_FALLBACK_RELEASES
        try:
            physical.RESOLVED_OVERTURE_PM=None
            physical.RESOLVED_OVERTURE_RELEASE=None
            physical.OVERTURE_PM_OVERRIDE=''
            physical.OVERTURE_RELEASE='2026-06-17.0'
            physical.OVERTURE_FALLBACK_RELEASES=('2026-05-20.0','2026-04-15.0')
            with patch.object(physical,'probe_pmtiles',side_effect=[(False,'HTTP 404'),(True,'HTTP 206')]) as probe:
                url,release=physical.resolve_overture_pmtiles()
            self.assertEqual(release,'2026-05-20.0')
            self.assertTrue(url.endswith('/2026-05-20.0/transportation.pmtiles'))
            self.assertEqual(probe.call_count,2)
        finally:
            physical.RESOLVED_OVERTURE_PM=old_url
            physical.RESOLVED_OVERTURE_RELEASE=old_release
            physical.OVERTURE_PM_OVERRIDE=old_override
            physical.OVERTURE_RELEASE=old_requested
            physical.OVERTURE_FALLBACK_RELEASES=old_fallbacks


if __name__ == '__main__':
    unittest.main()
