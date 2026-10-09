# Exploratory network review script 2. Run from the repo root: .venv/bin/python gis/analysis/network_review_2.py
# Reads the committed Madison snapshot and generated files; changes nothing.
import json, collections as C, math
W='priv/worlds/madison/'
E=json.load(open(W+'edges.geojson'))['features']; N={f['id']:f for f in json.load(open(W+'nodes.geojson'))['features']}
prov=json.load(open(W+'provenance.json')); ext=prov['import_extent']['coordinates'][0]
west=min(p[0] for p in ext); east=max(p[0] for p in ext); south=min(p[1] for p in ext); north=max(p[1] for p in ext)
P=[(e['id'],e['properties'],e['geometry']['coordinates']) for e in E]
print("== footway subtypes (from tags retained?) ==")
print("props keys sample:",sorted(P[0][1].keys()))
print("\n== components ==")
comp=C.defaultdict(list)
for id_,p,c in P: comp[p['component']].append((id_,p,c))
def near_extent(coords,tol=0.0002):
    return any(abs(x-west)<tol or abs(x-east)<tol or abs(y-south)<tol or abs(y-north)<tol for x,y in coords)
for k in sorted(comp, key=lambda k:-len(comp[k])):
    if k==0: continue
    items=comp[k]; coords=[xy for _,_,c in items for xy in c]
    cx=sum(x for x,y in coords)/len(coords); cy=sum(y for x,y in coords)/len(coords)
    hws=C.Counter(p.get('highway') for _,p,_ in items); acc=C.Counter(p['access_status'] for _,p,_ in items)
    inside=any(p['inside_playable'] for _,p,_ in items)
    print(f"#{k:2} edges={len(items)} len={sum(p['length_m'] for _,p,_ in items):6.0f}m at ({cx:.5f},{cy:.5f}) inside_playable={inside!s:5} touches_extent={near_extent(coords)!s:5} {dict(hws)} {dict(acc)} tunnel={[p.get('tunnel') for _,p,_ in items if p.get('tunnel')][:1]} bridge={[p.get('bridge') for _,p,_ in items if p.get('bridge')][:1]}")
print("\n== dead ends (degree 1 nodes) ==")
d1=[n for n in N.values() if n['properties']['degree']==1]
at_ext=[n for n in d1 if near_extent([n['geometry']['coordinates']])]
inside=[n for n in d1 if n['properties']['inside_playable']]
print("degree-1 nodes:",len(d1),"| at import-extent edge (truncation artifacts):",len(at_ext),"| inside playable:",len(inside))
adj=C.defaultdict(list)
for id_,p,c in P: adj[p['from']].append(p); adj[p['to']].append(p)
kinds=C.Counter()
for n in inside:
    ed=adj[n['id']][0]; kinds[(ed.get('highway'),ed.get('service'),ed['access_status'])]+=1
print("inside-playable dead ends by (highway, service, access):",dict(kinds.most_common(10)))
print("\n== layers / bridges / tunnels ==")
print("edges with layer tag:",C.Counter(str(p.get('layer')) for _,p,_ in P if p.get('layer') is not None))
vert=[(id_,p) for id_,p,_ in P if p.get('layer') not in (None,'0')]
# nodes where edges of different layers meet
nl=C.defaultdict(set)
for id_,p,_ in P:
    for n in (p['from'],p['to']): nl[n].add(str(p.get('layer') or '0')+('b' if p.get('bridge') else '')+('t' if p.get('tunnel') else ''))
mix=[n for n,s in nl.items() if len(s)>1]
print("nodes joining different layer/bridge/tunnel edges:",len(mix),"(ramps/stairs expected); sample:",[(n,sorted(nl[n])) for n in mix[:4]])
print("tunnel values:",C.Counter(p.get('tunnel') for _,p,_ in P if p.get('tunnel')),"| bridge values:",C.Counter(p.get('bridge') for _,p,_ in P if p.get('bridge')))
print("\n== parallel sidewalk/street ==")
streets=[(id_,c) for id_,p,c in P if p['classification']=='street']
print("street edges:",len(streets),"path edges:",sum(1 for _,p,_ in P if p['classification']=='path'),"alley:",sum(1 for _,p,_ in P if p['classification']=='alley'))
# edges per physical block: crude: total length by class
lt=C.Counter(); 
for _,p,_ in P: lt[p['classification']]+=p['length_m']
print("length_m by class:",{k:round(v) for k,v in lt.items()})
