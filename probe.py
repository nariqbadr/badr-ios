import json, urllib.request
B="https://bawazirquran.com/wp-admin/admin-ajax.php?action=bz&do="
def get(q): return json.load(urllib.request.urlopen(B+q, timeout=60))
d=get("data"); d=d.get('data',d)
rt=(d.get('readable') or {}).get('tracks') or {}
print('readable', {k:(type(v).__name__, len(v) if hasattr(v,'__len__') else v) for k,v in d['readable'].items()})
print('readable keys', type(rt), len(rt))
tracks={t['id']:t for t in d.get('recitations',d.get('tracks',[]))} if isinstance(d.get('recitations',d.get('tracks')),list) else {}
print('tracks', len(tracks), list(d.keys())[:40])
for k,v in (rt.items() if isinstance(rt,dict) else []):
    try: j=get("track_times&id="+k)
    except Exception as e: print(k,'ERR',e); continue
    ex=j.get('extra') or []
    surs=[j.get('surah')]+[x.get('surah') for x in ex]
    if 67 in surs or 71 in surs or 68 in surs:
        t=tracks.get(k,{})
        print('== track',k,t.get('title','')[:80],'readable',v)
        print('main surah',j.get('surah'),'ayahs',len(j.get('ayahs',[])), 'first', (j.get('ayahs') or [[0]])[0], 'last', (j.get('ayahs') or [[0]])[-1])
        for x in ex:
            a=x.get('ayahs') or []
            print('  extra surah',x.get('surah'),'n',len(a),'from',a[0] if a else None,'to',a[-1] if a else None, 'keys', [kk for kk in x.keys() if kk not in('ayahs','words')])
        print('  fatiha parts', len(j.get('fatiha') or []))
        print('  other keys', [kk for kk in j.keys() if kk not in ('ayahs','words','extra','fatiha')])
        json.dump(j, open('out/'+k+'.json','w'), ensure_ascii=False)
