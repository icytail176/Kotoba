#!/usr/bin/env python3
"""One-time bootstrap and read-only validator. Python standard library only."""
import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import unicodedata
import uuid

ROOT = Path(__file__).resolve().parents[2]
NAMESPACE_UUID = '01dfa402-05c2-46ab-a30f-acd35aa26ac0'
BOOTSTRAP_CREATED_AT = '2026-10-05T01:47:03.778148Z'
LEVELS = {'N5': 802, 'N4': 755, 'N3': 1817, 'N2': 3206, 'N1': 4029}
HEADERS = ['expression', 'reading', 'meaningChinese', 'partOfSpeech', 'exampleJapanese', 'exampleChinese', 'jlptLevel', 'tags']
PIPELINES = ['Kotoba/Services/BuiltInWordBookService.swift', 'Kotoba/Services/PartOfSpeechTokenizer.swift']
TARGET = Path('shared/vocabulary/canonical_vocabulary.json')
LEDGER = Path('shared/vocabulary/canonical_identity_ledger.json')

def digest(data):
    return hashlib.sha256(data).hexdigest()

def encoded(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')

def hira(value):
    return ''.join(chr(ord(c)-0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in value)

def etymology_key(level, expression, reading):
    return (level.upper(), unicodedata.normalize('NFKC', expression.strip()), hira(unicodedata.normalize('NFKC', reading.strip())))

def equivalent(entry):
    return (entry['expression'].strip().removeprefix('〜'), hira(entry['reading'].strip().removeprefix('〜')))

def tokens(value, separator):
    return list(dict.fromkeys(t.strip() for t in value.split(separator) if t.strip()))

def read_csv(path, headers=None):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream)
        if headers is not None and reader.fieldnames != headers:
            raise ValueError(f'{path.name}: unexpected headers')
        rows = []
        for number, row in enumerate(reader, 2):
            if None in row or any(v is None for v in row.values()):
                raise ValueError(f'{path.name}:{number}: column count mismatch')
            rows.append({k: v.strip() for k, v in row.items()})
        return rows

def sources(repo, allow_count_change=False):
    side_path = repo / 'Kotoba/Resources/builtin_loanword_etymology.csv'
    side = read_csv(side_path, ['wordBook', 'expression', 'reading', 'sourceTerm', 'sourceLanguage', 'isWasei', 'isPartial'])
    etymologies = {}
    for row in side:
        key = etymology_key(row['wordBook'], row['expression'], row['reading'])
        if key in etymologies or row['wordBook'] not in LEVELS or not row['sourceTerm']:
            raise ValueError('invalid/duplicate loanword sidecar identity')
        if row['isWasei'].lower() not in ('true', 'false') or row['isPartial'].lower() not in ('true', 'false'):
            raise ValueError('invalid sidecar boolean')
        etymologies[key] = row
    files = [side_path.relative_to(repo).as_posix()]
    entries = []
    matched = set()
    for level, count in LEVELS.items():
        relative = f'Kotoba/Resources/eggrolls_kotoba_{level}_strict.csv'
        files.append(relative)
        rows = read_csv(repo / relative, HEADERS)
        if len(rows) != count and not allow_count_change:
            raise ValueError(f'{level}: actual {len(rows)}, frozen baseline {count}; review count change explicitly')
        exact = set()
        normalized = set()
        for row in rows:
            key = (row['expression'], row['reading'])
            if key in exact or row['jlptLevel'] != level or not all(row[k] for k in ('expression', 'reading', 'meaningChinese')):
                raise ValueError(f'{relative}: invalid lexical fields or within-book duplicate')
            exact.add(key)
            entry = dict(row, bookKey='jlpt-' + level.lower())
            norm = equivalent(entry)
            if norm in normalized:
                raise ValueError(f'{relative}: within-book equivalent collision')
            normalized.add(norm)
            entry['partOfSpeech'] = '/'.join(tokens(row['partOfSpeech'], '/'))
            entry['tags'] = tokens(row['tags'], ';')
            entry.update(loanwordSourceTerm=None, loanwordSourceLanguageCode=None, loanwordIsWasei=False, loanwordIsPartial=False)
            ek = etymology_key(level, row['expression'], row['reading'])
            etymology = etymologies.get(ek)
            if etymology:
                matched.add(ek)
                entry.update(loanwordSourceTerm=etymology['sourceTerm'], loanwordSourceLanguageCode=etymology['sourceLanguage'] or None,
                             loanwordIsWasei=etymology['isWasei'].lower() == 'true', loanwordIsPartial=etymology['isPartial'].lower() == 'true')
            entries.append(entry)
    unmatched = sorted(set(etymologies)-matched)
    if unmatched:
        raise ValueError(f'unmatched sidecar rows require review: {unmatched}')
    return entries, {f: digest((repo/f).read_bytes()) for f in files + PIPELINES}

def duplicate_audit(entries):
    result = {}
    for name, key in [('expression', lambda e:e['expression']), ('reading', lambda e:e['reading']),
                      ('expressionReading', lambda e:(e['expression'], e['reading'])), ('equivalent', equivalent)]:
        grouped = collections.defaultdict(list)
        for e in entries:
            grouped[key(e)].append(e)
        groups = [v for v in grouped.values() if len(v)>1]
        result[name] = {'groups':len(groups), 'entries':sum(map(len, groups)), 'excess':sum(len(v)-1 for v in groups),
                        'crossBookGroups':sum(len({e['bookKey'] for e in g})>1 for g in groups)}
    result['loanwordCoverage'] = sum(e['loanwordSourceTerm'] is not None for e in entries)
    result['loanwordLanguages'] = dict(sorted(collections.Counter(e['loanwordSourceLanguageCode'] for e in entries if e['loanwordSourceTerm']).items()))
    result['pitchTagCoverage'] = sum(any(t.startswith('音调:') for t in e['tags']) for e in entries)
    return result

def schema_check(value, schema, path='$'):
    """Validate the subset used by the checked-in JSON Schema, without packages."""
    types = {'object':dict, 'array':list, 'string':str, 'integer':int, 'boolean':bool, 'null':type(None)}
    expected = schema.get('type')
    if expected:
        expected = [expected] if isinstance(expected, str) else expected
        if not any(type(value) is types[t] for t in expected):
            raise ValueError(f'{path}: invalid type')
    if 'const' in schema and value != schema['const']:
        raise ValueError(f'{path}: invalid constant')
    if 'enum' in schema and value not in schema['enum']:
        raise ValueError(f'{path}: invalid enum')
    if isinstance(value, str) and ('minLength' in schema and len(value) < schema['minLength'] or 'pattern' in schema and not re.fullmatch(schema['pattern'], value)):
        raise ValueError(f'{path}: invalid string')
    if type(value) is int and value < schema.get('minimum', value):
        raise ValueError(f'{path}: below minimum')
    if isinstance(value, dict):
        properties = schema.get('properties', {})
        if set(schema.get('required', []))-value.keys():
            raise ValueError(f'{path}: missing required fields')
        if schema.get('additionalProperties') is False and value.keys()-properties.keys():
            raise ValueError(f'{path}: unknown fields')
        for key, item in value.items():
            if key in properties:
                schema_check(item, properties[key], path+'.'+key)
            elif isinstance(schema.get("additionalProperties"), dict):
                schema_check(item, schema["additionalProperties"], path+'.'+key)
    if isinstance(value, list):
        for i, item in enumerate(value):
            schema_check(item, schema.get('items', {}), f'{path}[{i}]')

LEXICAL = HEADERS + ['bookKey', 'loanwordSourceTerm', 'loanwordSourceLanguageCode', 'loanwordIsWasei', 'loanwordIsPartial']

def drift(manifest, actual):
    def grouped(rows):
        return {(e['bookKey'], e['expression'], e['reading']): {k:e[k] for k in LEXICAL} for e in rows}
    old, new = grouped(manifest['entries']), grouped(actual)
    added, removed = sorted(new.keys()-old.keys()), sorted(old.keys()-new.keys())
    changed = sorted(k for k in new.keys() & old.keys() if new[k] != old[k])
    return {'added':added, 'removed':removed, 'changed':changed}

def validate(repo, manifest=None):
    manifest = manifest or json.loads((repo/TARGET).read_text(encoding='utf-8'))
    schema_check(manifest, json.loads((repo/'shared/vocabulary/canonical_vocabulary.schema.json').read_text(encoding='utf-8')))
    ledger = json.loads((repo/LEDGER).read_text(encoding='utf-8'))
    ns = uuid.UUID(manifest['namespaceUUID'])
    if str(ns) != manifest['namespaceUUID'] or ledger['namespaceUUID'] != str(ns) or str(ns) != NAMESPACE_UUID or ledger.get('formatVersion') != 1:
        raise ValueError('namespace mismatch / noncanonical encoding')
    reserved = {key:(cid, anchor) for key,cid,anchor in ledger['identities']}
    if len(reserved) != len(ledger['identities']) or len({v[0] for v in reserved.values()}) != len(reserved):
        raise ValueError('duplicate reserved keys')
    keys, ids = set(), set()
    for e in manifest['books'] + manifest['entries']:
        key, cid = e['canonicalKey'], e['canonicalId']
        name = 'book:'+key if 'entryCount' in e else key
        if key in keys or cid in ids or str(uuid.UUID(cid)) != cid or str(uuid.uuid5(ns, name)) != cid:
            raise ValueError(f'invalid/duplicate canonical identity: {key}')
        if reserved.get(key) != (cid, e['identityAnchor']):
            raise ValueError(f'identity reservation changed/missing: {key}')
        keys.add(key); ids.add(cid)
    if set(reserved)-keys != set(manifest['retiredKeys']):
        raise ValueError('retired identities must remain reserved in ledger')
    books = {b['canonicalKey']:b for b in manifest['books']}
    if set(books) != {'jlpt-'+l.lower() for l in LEVELS}:
        raise ValueError('unknown/missing book')
    for e in manifest['entries']:
        if e['bookKey'] not in books or e['jlptLevel'] != books[e['bookKey']]['jlptLevel']:
            raise ValueError('unknown book or mismatched JLPT level')
    counts = collections.Counter(e['bookKey'] for e in manifest['entries'])
    if manifest['entryCount'] != len(manifest['entries']) or len(manifest['entries']) != sum(LEVELS.values()):
        raise ValueError('entryCount mismatch')
    for level, count in LEVELS.items():
        b=books['jlpt-'+level.lower()]
        if counts[b['canonicalKey']] != count or b['entryCount'] != count:
            raise ValueError(f'{level}: count mismatch')
    # Compare every existing reservation to Git's prior checked-in identity ledger.
    # First bootstrap has no parent ledger; later edits may append, never rewrite.
    if (repo/'.git').exists():
        prior=None
        for ref in ['HEAD^','HEAD']:
            result=subprocess.run(['git','show',ref+':'+LEDGER.as_posix()],cwd=repo,text=True,capture_output=True)
            if result.returncode==0:
                prior=json.loads(result.stdout)
                break
        if prior:
            if prior['namespaceUUID']!=ledger['namespaceUUID']:
                raise ValueError('immutable namespace changed from Git baseline')
            for key,cid,anchor in prior['identities']:
                if reserved.get(key)!=(cid,anchor):
                    raise ValueError('immutable reservation deleted/reassigned from Git baseline: '+key)
    actual, hashes = sources(repo, allow_count_change=True)
    changes = drift(manifest, actual)
    if any(changes.values()):
        raise ValueError('SOURCE DRIFT '+json.dumps(changes, ensure_ascii=False))
    for source in PIPELINES:
        if hashes[source] != manifest['generatedFrom']['sourceSha256'][source]:
            raise ValueError(f'PIPELINE DRIFT: {source}; review the extraction semantics, do not regenerate IDs')
    print(json.dumps({'validation':'PASS','entryCount':len(actual),'counts':dict(counts),'audit':duplicate_audit(actual),'drift':changes}, ensure_ascii=False, indent=2))
    return manifest

def bootstrap(repo):
    if (repo/TARGET).exists() or (repo/LEDGER).exists():
        raise ValueError('bootstrap refused: manifest/ledger already exists; never regenerate identities')
    entries, hashes = sources(repo)
    ns = uuid.UUID(NAMESPACE_UUID)  # Generated once; frozen for deterministic bootstrap replay.
    books=[]; identities=[]
    for level,count in LEVELS.items():
        key='jlpt-'+level.lower(); anchor=digest(encoded({'initialBookKey':key}))
        cid=str(uuid.uuid5(ns,'book:'+key))
        books.append(dict(canonicalKey=key,canonicalId=cid,identityAnchor=anchor,name='JLPT '+level,
                          description='内置 JLPT '+level+' 词书。',jlptLevel=level,entryCount=count))
        identities.append([key,cid,anchor])
    counters=collections.Counter()
    for e in entries:
        counters[e['bookKey']]+=1
        key=f"jlpt:{e['jlptLevel'].lower()}:{counters[e['bookKey']]:06d}"
        # Initial snapshot provenance, not the algorithm for permanent identity.
        anchor=digest(encoded({'initialBookKey':e['bookKey'],'initialExpression':e['expression'],
                               'initialReading':e['reading'],'initialOccurrence':counters[e['bookKey']]}))
        cid=str(uuid.uuid5(ns,key));e.update(canonicalKey=key,canonicalId=cid,identityAnchor=anchor)
        identities.append([key,cid,anchor])
    manifest=dict(formatVersion=1,manifestVersion=1,namespaceUUID=str(ns),createdAt=BOOTSTRAP_CREATED_AT,
                  generatedFrom={'sourceMacSeedVersion':8,'pipeline':'Mac seed-8 CSV + POS tokenization + tags + NFKC/hiragana sidecar matching','sourceSha256':hashes},
                  entryCount=len(entries),books=books,entries=entries,retiredKeys=[])
    (repo/TARGET).parent.mkdir(parents=True, exist_ok=True)
    with (repo/TARGET).open('x',encoding='utf-8') as stream:
        json.dump(manifest,stream,ensure_ascii=False,indent=2);stream.write('\n')
    with (repo/LEDGER).open('x',encoding='utf-8') as stream:
        json.dump({'formatVersion':1,'namespaceUUID':str(ns),'identities':identities},stream,ensure_ascii=False,separators=(',',':'));stream.write('\n')
    print('Namespace:',ns)
    validate(repo)

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command',choices=['bootstrap','validate'])
    parser.add_argument('--repo',type=Path,default=ROOT)
    args=parser.parse_args()
    try:
        bootstrap(args.repo) if args.command=='bootstrap' else validate(args.repo)
    except (ValueError, KeyError, OSError) as error:
        parser.exit(1, str(error)+'\n')
