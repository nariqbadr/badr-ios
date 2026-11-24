set -x
P=com.bawazirquran.app
mkdir -p shots
adb root; sleep 3
adb shell wm size 1080x2340; adb shell wm density 440; sleep 2
( for i in $(seq 1 400); do adb emu geo fix 31.3260 30.0890 >/dev/null 2>&1; sleep 3; done ) &
GEO=$!
KEYS="quran"
setpref() { # $1 key $2 value
  adb shell am force-stop $P
  F=/data/data/$P/shared_prefs/badr.xml
  adb shell "[ -f $F ] || echo '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?><map></map>' > $F"
  adb shell "sed -i 's#<string name=\"$1\">[^<]*</string>##; s#</map>#<string name=\"$1\">$2</string></map>#' $F"
}
setlong() { adb shell "sed -i 's#<long name=\"$1\" value=\"[^\"]*\" />##; s#</map>#<long name=\"$1\" value=\"$2\" /></map>#' /data/data/$P/shared_prefs/badr.xml"; }
perms() { for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS ACTIVITY_RECOGNITION; do adb shell pm grant $P android.permission.$perm || true; done; }
tapText() {
  timeout 30 adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; timeout 30 adb pull /sdcard/ui.xml /tmp/ui.xml >/dev/null 2>&1
  B=$(python3 - "$1" <<'PY'
import re,sys
try: x=open('/tmp/ui.xml',encoding='utf-8').read()
except Exception: x=''
for m in re.finditer(r'<node [^>]*>', x):
    n=m.group(0)
    if sys.argv[1] in n:
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
        if b:
            a=list(map(int,b.groups())); print((a[0]+a[2])//2,(a[1]+a[3])//2); break
PY
)
  echo "tap $1 -> $B"; [ -n "$B" ] && adb shell input tap $B
}

rec() { # $1 name, $2 seconds: record the screen in the background
  adb shell rm -f /sdcard/$1.mp4
  adb shell screenrecord --time-limit $2 --bit-rate 5000000 --size 720x1560 /sdcard/$1.mp4 &
  RECPID=$!; sleep 1
}
endrec() { sleep 2; adb shell pkill -INT screenrecord 2>/dev/null; wait $RECPID 2>/dev/null; sleep 2; adb pull /sdcard/$1.mp4 shots/$1.mp4 >/dev/null 2>&1; }
up() { adb shell input swipe 540 1500 540 700 600; sleep ${1:-1.5}; }
down() { adb shell input swipe 540 700 540 1500 600; sleep ${1:-1.5}; }
snap() { timeout 30 adb exec-out screencap -p > "shots/t_$1.png"; }
playing() { local pid=$(adb shell pidof $P | tr -d "\r"); [ -z "$pid" ] && { echo "0 (app closed)"; return; }; echo "$(adb shell dumpsys audio | grep -E "u/pid:[0-9]+/$pid " | grep -c "state:started")"; }


up() { adb shell input swipe 540 1500 540 700 600; sleep ${1:-1.5}; }
snap() { timeout 30 adb exec-out screencap -p > "shots/b_$1.png"; }

setup() {
  adb uninstall $P >/dev/null 2>&1; adb install -r $1 > shots/install_$2.txt 2>&1; perms
  adb shell am start -W -n $P/.MainActivity > /dev/null; sleep 20
  setpref onboarded 1; setpref lang ar; setlong lat 4629159534621622691; setlong lng 4629503834813135166
  U=$(adb shell stat -c %u /data/data/$P | tr -d "\r"); adb shell "mkdir -p /data/data/$P/no_backup && touch /data/data/$P/no_backup/onboarded && chown -R $U:$U /data/data/$P/no_backup && restorecon -R /data/data/$P/no_backup"
}
go() { adb shell am force-stop $P; timeout 40 adb shell am start -W -n $P/.MainActivity --ez shot true --es open "$1" > /dev/null; sleep ${2:-14}; }
cliptest() { # $1 tag
  adb logcat -c; (adb logcat -v time > shots/live_$1.txt 2>&1 &)
  go clip 40; snap ${1}_open
  rec rec_$1 175; tapText "تصدير"; sleep 3; snap ${1}_t0
  for k in 1 2 3 4 5; do sleep 30; snap ${1}_t$k; done
  endrec rec_$1
  pkill -f "adb logcat" || true
}
CLIP=$(curl -s --max-time 60 "https://bawazirquran.com/wp-admin/admin-ajax.php?action=bz&do=data" | python3 -c "
import json,sys
d=json.load(sys.stdin); d=d.get('data',d); r=d.get('readable',{}).get('tracks',{})
ts=[t for t in d.get('recitations',[]) if ((t.get('video') or {}).get('q')) and t.get('id') in r]
ts.sort(key=lambda t:(t.get('publishAt') or t.get('createdAt') or '', t.get('order',0)), reverse=True)
print(ts[0]['id'] if ts else '')" 2>/dev/null); echo "CLIP=$CLIP"
mkdir -p shots
curl -s --max-time 60 "https://bawazirquran.com/wp-admin/admin-ajax.php?action=bz&do=data" > /tmp/data.json
python3 - > shots/probe2.txt 2>&1 <<'PY'
import json, urllib.request, urllib.parse, subprocess
d=json.load(open('/tmp/data.json')); d=d.get('data',d)
site='https://bawazirquran.com/'
def media(s):
    s=(s or '').strip()
    if s.startswith('http'): return s.replace(' ','%20')
    if s.startswith('//'): return 'https:'+s
    return site+'/'.join(urllib.parse.quote(p) for p in s.split('/') if p)
rd=d.get('readable',{}).get('tracks',{})
tr={t['id']:t for t in d.get('recitations',[])}
recs={r['id']:r.get('name') for r in d.get('reciters',[])}
hits=[(k,v) for k,v in rd.items() if len(v)>=3 and v[0]==24 and v[1]<=35 and v[2]>=36]
print('readable sample', list(rd.items())[:8], len(rd)); print('keys', list(d.keys())[:30]); print('tracks for 24:35-36', hits)
for k,v in rd.items():
    t=tr.get(k,{})
    if 'التركي' in (recs.get(t.get('reciterId')) or ''): print(' turki', k, v, t.get('reciterId'))
mk=d.get('site',{}).get('maker') or {}
print('maker cfg', {x:mk.get(x) for x in ['defaultReciter','defaultSurah','defaultFrom','defaultTo']})
hits=[(k,v) for k,v in rd.items() if len(v)>=3 and v[0]==24]
print('surah 24', hits)
for k,v in hits:
    t=tr.get(k,{}); print('\n==',k, recs.get(t.get('reciterId')), 'audio', t.get('audio'), 'video', bool((t.get('video') or {}).get('q')))
    j=json.load(urllib.request.urlopen(site+'wp-admin/admin-ajax.php?action=bz&do=track_times&id='+urllib.parse.quote(k), timeout=60))
    print(' ok', j.get('ok'), 'surah', j.get('surah'), 'url', j.get('url'), 'n ayahs', len(j.get('ayahs') or []))
    ay=[a for a in (j.get('ayahs') or []) if a and a[0] in (34,35,36,37)]; print(' times', ay)
    print(' first/last', (j.get('ayahs') or [None])[0], (j.get('ayahs') or [None])[-1])
    u=media(j.get('url') or t.get('audio'))
    print(' media', u)
    try:
        out=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration,format_name:stream=codec_name,sample_rate,channels','-of','default=nw=1',u],capture_output=True,text=True,timeout=120); print(out.stdout, out.stderr[:300])
    except Exception as e: print(' ffprobe', e)
PY
kill $GEO 2>/dev/null || true
