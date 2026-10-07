#!/usr/bin/env python3
"""Bounded JOVRA planning checks. No media reads, rendering, cloud or writes."""
import json
import re
import sys
from fractions import Fraction
from pathlib import Path

PROFILES = {'coach-cut', 'match-broadcast', 'rally-pulse', 'progress-story', 'court-memories'}
PROVENANCE = {'manual', 'estimated', 'reviewed', 'validated'}

def require(condition, message):
    if not condition:
        raise ValueError(message)

def fields(obj, keys, label):
    require(type(obj) is dict and set(obj) == set(keys.split()), label + ': missing or unknown fields')

def integer(value, label, minimum=0):
    require(type(value) is int and value >= minimum, label + ': invalid integer')
    return value

def identifier(value, label):
    require(type(value) is str and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,95}', value), label + ': invalid identifier')

def fps(value):
    fields(value, 'num den', 'fps')
    f = Fraction(integer(value['num'], 'fps numerator', 1), integer(value['den'], 'fps denominator', 1))
    require(1 <= f <= 120, 'fps outside starter limits')
    return f

def validate(plan):
    fields(plan, 'schemaVersion projectId sample sourceManifestRevision syncRevision eventRevision profileId profileRevision output sources segments audio', 'plan')
    require(plan['schemaVersion'] == 'jovra.edit-plan/1', 'unsupported version')
    identifier(plan['projectId'], 'projectId')
    require(type(plan['sample']) is bool, 'sample must be boolean')
    for key in ('sourceManifestRevision', 'syncRevision', 'eventRevision', 'profileRevision'):
        integer(plan[key], key, 1)
    require(type(plan['profileId']) is str and plan['profileId'] in PROFILES, 'unknown profile')
    out = plan['output']
    fields(out, 'fps width height totalFrames container videoCodec audioCodec', 'output')
    rate = fps(out['fps'])
    for key in ('width', 'height'):
        size = integer(out[key], key, 2)
        require(size % 2 == 0 and size <= 3840, 'unsupported dimensions')
    total = integer(out['totalFrames'], 'totalFrames', 1)
    require(Fraction(total, 1) / rate <= 14400, 'output exceeds four-hour starter limit')
    require((out['container'], out['videoCodec'], out['audioCodec']) == ('mp4', 'h264', 'aac'), 'unsupported output format')
    require(type(plan['sources']) is list and 1 <= len(plan['sources']) <= 6, 'one to six sources required')
    sources = {}
    for source in plan['sources']:
        fields(source, 'id sha256 fps width height frameCount hasAudio', 'source')
        identifier(source['id'], 'source id')
        require(source['id'] not in sources, 'duplicate source')
        require(type(source['sha256']) is str and re.fullmatch(r'[0-9a-f]{64}', source['sha256']), 'invalid declared hash')
        require(fps(source['fps']) == rate, 'normalize source FPS first')
        require(type(source['width']) is int and type(source['height']) is int, 'invalid source dimensions')
        require((source['width'], source['height']) == (out['width'], out['height']), 'normalize dimensions first')
        count = integer(source['frameCount'], 'source frameCount', 1)
        require(Fraction(count, 1) / rate <= 14400, 'source exceeds starter limit')
        require(type(source['hasAudio']) is bool, 'hasAudio must be boolean')
        sources[source['id']] = source
    require(type(plan['segments']) is list and 1 <= len(plan['segments']) <= 128, 'invalid segment count')
    cursor = 0
    seen = set()
    for segment in plan['segments']:
        fields(segment, 'id sourceId sourceInFrame sourceOutFrame outputInFrame outputOutFrame speed transition overlayRefs', 'segment')
        identifier(segment['id'], 'segment id')
        require(segment['id'] not in seen, 'duplicate segment id')
        seen.add(segment['id'])
        identifier(segment['sourceId'], 'segment source id')
        require(segment['sourceId'] in sources, 'unknown source')
        for key in ('sourceInFrame', 'sourceOutFrame', 'outputInFrame', 'outputOutFrame'):
            integer(segment[key], key)
        require(segment['outputInFrame'] == cursor, 'output gap or overlap')
        duration = segment['outputOutFrame'] - segment['outputInFrame']
        require(duration > 0 and segment['outputOutFrame'] <= total, 'invalid output interval')
        require(0 <= segment['sourceInFrame'] < segment['sourceOutFrame'] <= sources[segment['sourceId']]['frameCount'], 'source window exceeds declared coverage')
        require(type(segment['speed']) in (int, float) and segment['speed'] == 1, 'starter accepts 1x cuts only')
        require(segment['sourceOutFrame'] - segment['sourceInFrame'] == duration, 'source/output duration mismatch')
        require(segment['transition'] == 'cut', 'unsupported transition')
        require(type(segment['overlayRefs']) is list and len(segment['overlayRefs']) <= 8, 'invalid overlay refs')
        for overlay in segment['overlayRefs']:
            fields(overlay, 'kind refId eventRevision provenance', 'overlay')
            require(type(overlay['kind']) is str and overlay['kind'] in {'score', 'metric', 'note'}, 'unsupported overlay')
            identifier(overlay['refId'], 'overlay ref')
            integer(overlay['eventRevision'], 'overlay eventRevision', 1)
            require(overlay['eventRevision'] == plan['eventRevision'], 'stale event revision')
            require(type(overlay['provenance']) is str and overlay['provenance'] in PROVENANCE, 'invalid provenance')
        cursor = segment['outputOutFrame']
    require(cursor == total, 'incomplete output coverage')
    audio = plan['audio']
    fields(audio, 'mode sourceId sourceInFrame sourceOutFrame', 'audio')
    integer(audio['sourceInFrame'], 'audio in')
    integer(audio['sourceOutFrame'], 'audio out')
    if audio['mode'] == 'silence':
        require(audio['sourceId'] is None and audio['sourceInFrame'] == audio['sourceOutFrame'] == 0, 'silence must not bind audio')
    else:
        require(audio['mode'] == 'primary-bed', 'unsupported audio route')
        identifier(audio['sourceId'], 'audio source id')
        require(audio['sourceId'] in sources and sources[audio['sourceId']]['hasAudio'], 'audio source unavailable')
        require(0 <= audio['sourceInFrame'] < audio['sourceOutFrame'] <= sources[audio['sourceId']]['frameCount'], 'audio window exceeds coverage')
        require(audio['sourceOutFrame'] - audio['sourceInFrame'] == total, 'audio does not cover output')
    return {'status': 'valid-planning-subset', 'sample': plan['sample'], 'segments': len(plan['segments']), 'frames': total, 'durationSeconds': float(Fraction(total, 1) / rate), 'actualMediaVerified': False, 'rendered': False}

def main():
    require(len(sys.argv) == 2, 'usage: validate_edit_plan.py plan.json')
    path = Path(sys.argv[1])
    require(path.stat().st_size <= 2_000_000, 'plan exceeds two MB')
    print(json.dumps(validate(json.loads(path.read_text())), indent=2))

if __name__ == '__main__':
    try:
        main()
    except (ValueError, TypeError, KeyError, OSError) as exc:
        print(json.dumps({'status': 'rejected', 'reason': str(exc)}), file=sys.stderr)
        sys.exit(1)
