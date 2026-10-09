# Exploratory network review script 3. Run from the repo root: .venv/bin/python gis/analysis/network_review_3.py
# Reads the committed Madison snapshot and generated files; changes nothing.
import json, collections as C, xml.etree.ElementTree as ET
W='priv/worlds/madison/'
root=ET.parse(W+'source/snapshot.osm').getroot()
tags={w.get('id'):{t.get('k'):t.get('v') for t in w.findall('tag')} for w in root.findall('way')}
E=json.load(open(W+'edges.geojson'))['features']; N={f['id']:f for f in json.load(open(W+'nodes.geojson'))['features']}
def sub(p):
    t=tags.get(str(p['osm_ids'][0]),{})
    if p.get('highway')=='footway': return 'footway/'+(t.get('footway') or 'plain')
    return p.get('highway')+('/'+t['service'] if t.get('service') else '')
print("== edge counts by source subtype ==")
cnt=C.Counter(sub(e['properties']) for e in E); print(dict(cnt.most_common(14)))
deg=lambda n:N[n]['properties']['degree']
print("\n== dead-end edges (inside playable) by subtype ==")
de=[e for e in E if e['properties']['inside_playable'] and (deg(e['properties']['from'])==1 or deg(e['properties']['to'])==1)]
print(len(de), dict(C.Counter(sub(e['properties']) for e in de).most_common(10)))
print("\n== crossings ==")
cr=[e for e in E if sub(e['properties'])=='footway/crossing']
dang=[e for e in cr if deg(e['properties']['from'])==1 or deg(e['properties']['to'])==1]
print("crossing edges:",len(cr),"| with a dangling end:",len(dang),"| both ends connected:",len(cr)-len(dang))
cr_tags=C.Counter((tags.get(str(e['properties']['osm_ids'][0]),{}).get('crossing') or '-') for e in cr); print("crossing=* values:",dict(cr_tags.most_common(6)))
print("\n== sidewalks ==")
sw=[e for e in E if sub(e['properties'])=='footway/sidewalk']
swd=[e for e in sw if deg(e['properties']['from'])==1 or deg(e['properties']['to'])==1]
print("sidewalk edges:",len(sw),"| with dangling end:",len(swd),"| total length m:",round(sum(e['properties']['length_m'] for e in sw)))
print("\n== plain footways (no footway=* tag) ==")
pf=[e for e in E if sub(e['properties'])=='footway/plain']
print(len(pf),"| dangling:",sum(1 for e in pf if deg(e['properties']['from'])==1 or deg(e['properties']['to'])==1))
print("\n== do street edges have a parallel sidewalk? ==")
named=C.Counter(tags.get(str(e['properties']['osm_ids'][0]),{}).get('sidewalk') for e in E if e['properties']['classification']=='street' and e['properties'].get('highway') in('residential','tertiary','secondary','primary'))
print("sidewalk=* on streets:",dict(named))
print("\n== way tags not retained by importer but present (counts over graph ways) ==")
keys=C.Counter()
for e in E:
    for k in tags.get(str(e['properties']['osm_ids'][0]),{}): keys[k]+=1
print(dict(keys.most_common(40)))
