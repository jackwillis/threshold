# Exploratory network review script 4. Run from the repo root: .venv/bin/python gis/analysis/network_review_4.py
# Reads the committed Madison snapshot and generated files; changes nothing.
import json, collections as C
from shapely.geometry import shape, Point
from shapely.strtree import STRtree
W='priv/worlds/madison/'
E=json.load(open(W+'edges.geojson'))['features']; N={f['id']:f for f in json.load(open(W+'nodes.geojson'))['features']}
X=json.load(open(W+'context.geojson'))['features']
plazas=[shape(f['geometry']) for f in X if f['properties']['classification']=='pedestrian_area']
buildings=[shape(f['geometry']) for f in X if f['properties']['classification']=='building']
tp=STRtree(plazas); tb=STRtree(buildings)
TOL=0.00003  # about 3 m
def near(tree,geoms,pt,tol=TOL):
    return any(geoms[i].distance(pt)<=tol for i in tree.query(pt.buffer(tol)))
deg=lambda n:N[n]['properties']['degree']
dead=[]
for e in E:
    p=e['properties']
    if not p['inside_playable']: continue
    for end in ('from','to'):
        if deg(p[end])==1: dead.append((e,N[p[end]]))
print("dead-end endpoints inside playable:",len(dead))
c=C.Counter()
for e,n in dead:
    pt=Point(n['geometry']['coordinates']); hw=e['properties'].get('highway'); sv=e['properties'].get('service')
    kind='driveway/parking' if sv in('driveway','parking_aisle') else hw
    c[(kind,'at plaza' if near(tp,plazas,pt) else 'at building' if near(tb,buildings,pt) else 'free')]+=1
for k,v in sorted(c.items(), key=lambda kv:-kv[1])[:14]: print(f"  {k[0]:18}{k[1]:12}{v}")
tot=C.Counter(k[1] for k,v in c.elements() for _ in [0])
print("totals by situation:",dict(C.Counter({s:sum(v for (k,s2),v in c.items() if s2==s) for s in('at plaza','at building','free')})))
# plazas that touch several edge endpoints: how much do they connect?
touch=C.Counter()
for i,pl in enumerate(plazas):
    ends=sum(1 for e,n in dead if pl.distance(Point(n['geometry']['coordinates']))<=TOL)
    touch[ends]+=1
print("pedestrian_area polygons by number of dangling footway ends touching them:",dict(sorted(touch.items())))
# small components touching plazas/buildings
print("\nsmall components (inside playable) and what their endpoints touch:")
comp=C.defaultdict(list)
for e in E: comp[e['properties']['component']].append(e)
for k,items in sorted(comp.items()):
    if k==0 or not any(x['properties']['inside_playable'] for x in items): continue
    pts=set()
    for x in items: pts|={x['properties']['from'],x['properties']['to']}
    tags=[]
    for n in pts:
        pt=Point(N[n]['geometry']['coordinates'])
        tags.append('plaza' if near(tp,plazas,pt) else 'building' if near(tb,buildings,pt) else 'free')
    print(f"  #{k:2} {len(items)} edges: endpoints touching {dict(C.Counter(tags))}")
