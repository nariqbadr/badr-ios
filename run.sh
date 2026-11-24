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
python3 - > shots/probe.txt 2>&1 <<'PY'
import json, urllib.request, time, struct, urllib.parse
d=json.load(open('/tmp/data.json')); d=d.get('data',d)
site='https://bawazirquran.com/'
def media(s):
    s=(s or '').strip()
    if s.startswith('http'): return s.replace(' ','%20')
    if s.startswith('//'): return 'https:'+s
    return site+'/'.join(urllib.parse.quote(p) for p in s.split('/') if p)
vs=[t for t in d.get('recitations',[]) if (t.get('video') or {}).get('q')]
print('videos', len(vs))
for t in vs[:4]:
    for q in t['video']['q'][:2]:
        u=media(q.get('url')); print('\n==', t.get('id'), q.get('h'), u)
        try:
            r=urllib.request.Request(u, method='HEAD'); t0=time.time(); res=urllib.request.urlopen(r, timeout=30)
            print('HEAD', res.status, 'final', res.geturl()); 
            for k in ['Content-Length','Accept-Ranges','Content-Type','Server','Cache-Control','CF-Cache-Status','X-Cache']: print(' ',k, res.headers.get(k))
            size=int(res.headers.get('Content-Length') or 0)
            # top-level atoms via range requests
            off=0; atoms=[]
            while off < size and len(atoms) < 8:
                rr=urllib.request.Request(u, headers={'Range':f'bytes={off}-{off+15}'}); t1=time.time(); b=urllib.request.urlopen(rr, timeout=30); data=b.read()
                if len(data)<8: break
                sz,typ=struct.unpack('>I4s',data[:8]); 
                if sz==1: sz=struct.unpack('>Q',data[8:16])[0]
                atoms.append((typ.decode('latin1'), off, sz, b.status, round(time.time()-t1,2)))
                if sz<8: break
                off+=sz
            print('  atoms', atoms)
            # speed: first 4 MB
            rr=urllib.request.Request(u, headers={'Range':'bytes=0-4194303'}); t1=time.time(); n=len(urllib.request.urlopen(rr, timeout=60).read()); dt=time.time()-t1
            print('  4MB in', round(dt,2),'s', round(n/dt/1e6,2),'MB/s')
        except Exception as e: print('  ERR', e)
PY
kill $GEO 2>/dev/null || true
