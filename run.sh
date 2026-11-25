set -x
mkdir -p shots/fonts
curl -s --max-time 60 "https://bawazirquran.com/wp-admin/admin-ajax.php?action=bz&do=data" > /tmp/d.json
python3 - <<'PY'
import json,urllib.parse,subprocess
d=json.load(open('/tmp/d.json')); d=d.get('data',d)
site=d.get('site',{}); fonts=(site.get('maker') or {}).get('fonts') or []
json.dump(fonts,open('shots/fonts/list.json','w'),ensure_ascii=False,indent=1)
for i,f in enumerate(fonts):
    u=f.get('url','')
    if not u.startswith('http'): u='https://bawazirquran.com/'+urllib.parse.quote(u.lstrip('/'))
    ext=u.rsplit('.',1)[-1][:5]
    subprocess.run(['curl','-s','-L','--max-time','60','-o',f'shots/fonts/f{i}.{ext}',u])
# also a sample of ayah text with uthmani marks
q=d.get('quranFull') or {}
json.dump({k:q.get(k) for k in ('base','id')},open('shots/fonts/q.json','w'))
PY
ls -la shots/fonts
