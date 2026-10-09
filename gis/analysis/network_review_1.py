# Exploratory network review script 1. Run from the repo root: .venv/bin/python gis/analysis/network_review_1.py
# Reads the committed Madison snapshot and generated files; changes nothing.
import json, collections as C, xml.etree.ElementTree as ET
W='priv/worlds/madison/'
root=ET.parse(W+'source/snapshot.osm').getroot()
def tags(e): return {t.get('k'):t.get('v') for t in e.findall('tag')}
ways=[(w,tags(w)) for w in root.findall('way')]
hw=[(w,t) for w,t in ways if 'highway' in t and t.get('area')!='yes']
GRAPH={"residential","living_street","service","pedestrian","footway","path","steps","track","unclassified","tertiary","tertiary_link","secondary","secondary_link","primary","primary_link","road","cycleway"}
g=[(w,t) for w,t in hw if t['highway'] in GRAPH]
print("graph-eligible ways:",len(g), "| dropped highway types:",dict(C.Counter(t['highway'] for w,t in hw if t['highway'] not in GRAPH)))
print("\n== DIRECTION ==")
for k in ['oneway','oneway:foot','oneway:bicycle','foot','access','foot:conditional','access:conditional','bicycle','motor_vehicle','vehicle','conditional','incline','ramp','wheelchair','segregated']:
    c=C.Counter(t[k] for w,t in g if k in t)
    if c: print(f"{k:20}",sum(c.values()),dict(c.most_common(8)))
print("oneway ways by highway:",dict(C.Counter(t['highway'] for w,t in g if t.get('oneway') in('yes','-1','true','1'))))
print("\n== ACCESS (ways) ==")
print("no access tag at all:",sum(1 for w,t in g if not any(k in t for k in('foot','access'))),"of",len(g))
for hwt in sorted({t['highway'] for w,t in g}):
    sub=[t for w,t in g if t['highway']==hwt]
    acc=C.Counter((t.get('foot') or t.get('access') or '-') for t in sub)
    print(f"{hwt:16}{len(sub):5}  foot/access:",dict(acc.most_common(6)))
print("\n== service subtypes x access ==")
for st in ['driveway','parking_aisle','alley','drive-through','emergency_access',None]:
    sub=[t for w,t in g if t['highway']=='service' and t.get('service')==st]
    if sub: print(f"{str(st):18}{len(sub):4}",dict(C.Counter((t.get('access') or '-')+'/'+(t.get('foot') or '-') for t in sub).most_common(5)))
