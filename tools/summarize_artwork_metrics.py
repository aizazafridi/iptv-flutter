"""Summarize opt-in artwork logs, excluding unrelated application output.
Usage: python tools/summarize_artwork_metrics.py run.log [other-run.log]
No network access, credentials, URLs, or source log lines are emitted.
"""
import collections
import json
import math
import pathlib
import sys


def load(path):
    raw = pathlib.Path(path).read_bytes()
    content = raw.decode('utf-16' if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig', errors='replace')
    rows = []
    for line in content.splitlines():
        if 'ARTWORK_METRIC ' not in line:
            continue
        try:
            row = json.loads(line.split('ARTWORK_METRIC ', 1)[1])
            if isinstance(row, dict) and isinstance(row.get('phase'), str):
                rows.append(row)
        except (ValueError, TypeError):
            continue
    return rows


def distribution(values):
    values = sorted(v for v in values if isinstance(v, (float, int)))
    if not values:
        return {'count': 0, 'p50': None, 'p95': None}
    return {'count': len(values), 'p50': values[math.ceil(len(values) * .5) - 1], 'p95': values[math.ceil(len(values) * .95) - 1]}


def summarize(rows):
    by_phase = collections.defaultdict(list)
    for row in rows:
        by_phase[row['phase']].append(row)
    first_poster = []
    first_backdrop = []
    origin = None
    seen = set()
    in_flight = collections.Counter()
    overlaps = 0
    for row in rows:
        phase = row['phase']
        if phase in ('catalog_open', 'details_open'):
            origin = row.get('us')
            seen.clear()
        if phase == 'http_start':
            key = row.get('id')
            overlaps += int(in_flight[key] > 0)
            in_flight[key] += 1
        elif phase in ('http_end', 'http_error'):
            key = row.get('id')
            in_flight[key] = max(0, in_flight[key] - 1)
        if phase == 'first_display_frame' and row.get('visible') and origin is not None:
            kind = row.get('kind')
            if kind not in seen:
                seen.add(kind)
                elapsed = (row['us'] - origin) / 1000
                if kind == 'poster':
                    first_poster.append(elapsed)
                elif kind == 'backdrop':
                    first_backdrop.append(elapsed)
    snapshots = by_phase['snapshot']
    return {
        'event_count': len(rows),
        'http_attempts': len(by_phase['http_start']),
        'overlapping_http_attempts_for_same_asset': overlaps,
        'response_body_bytes': sum(r.get('body_bytes', 0) for r in by_phase['http_end']),
        'cache_file_sources': dict(collections.Counter(r.get('source') for r in by_phase['file_ready'])),
        'memory_keep_alive_hits': sum(bool(r.get('keep_alive')) for r in by_phase['memory_lookup']),
        'queue_wait_ms': distribution([r.get('queue_ms') for r in by_phase['http_start']]),
        'download_ms': distribution([r.get('download_ms') for r in by_phase['http_end']]),
        'file_read_plus_decode_and_schedule_ms': distribution([r.get('file_to_decoded_ms') for r in by_phase['decoded_frame_ready']]),
        'first_visible_poster_from_page_open_ms': distribution(first_poster),
        'first_backdrop_from_page_open_ms': distribution(first_backdrop),
        'movie_details_usable_ms': distribution([r.get('elapsed_ms') for r in by_phase['details_usable_frame'] if r.get('type') == 'movies']),
        'cast_url_ready_to_display_ms': distribution([r.get('elapsed_ms') for r in by_phase['first_display_frame'] if r.get('kind') == 'cast']),
        'peak_cached_image_bytes': max((r.get('peak_cached_image_bytes', 0) for r in snapshots), default=None),
        'last_frame_snapshot': {k: snapshots[-1].get(k) for k in ('frames', 'build_over_budget', 'raster_over_budget', 'refresh_hz')} if snapshots else None,
        'notes': ['Missing values mean not measured.', 'Body bytes exclude headers/TLS and may reflect decompression.', 'Frame budget misses are not a count of dropped display frames.', 'Cold/warm classification must come from the run procedure.'],
    }


if __name__ == '__main__':
    if not sys.argv[1:]:
        raise SystemExit('Usage: summarize_artwork_metrics.py run.log [other-run.log]')
    print(json.dumps([{'run': pathlib.Path(path).name, 'metrics': summarize(load(path))} for path in sys.argv[1:]], indent=2))
