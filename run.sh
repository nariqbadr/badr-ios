set -x
P=com.bawazirquran.app
mkdir -p shots
adb root; sleep 3
adb shell wm size 1080x2340; adb shell wm density 440; sleep 2
( for i in $(seq 1 400); do adb emu geo fix 31.3016 30.0784 >/dev/null 2>&1; sleep 3; done ) &
GEO=$!
KEYS=""
setpref() { # $1 key $2 value
  adb shell am force-stop $P
  F=/data/data/$P/shared_prefs/badr.xml
  adb shell "[ -f $F ] || echo '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?><map></map>' > $F"
  adb shell "sed -i 's#<string name=\"$1\">[^<]*</string>##; s#</map>#<string name=\"$1\">$2</string></map>#' $F"
}
setlong() { adb shell "sed -i 's#<long name=\"$1\" value=\"[^\"]*\" />##; s#</map>#<long name=\"$1\" value=\"$2\" /></map>#' /data/data/$P/shared_prefs/badr.xml"; }
perms() { for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS ACTIVITY_RECOGNITION; do adb shell pm grant $P android.permission.$perm || true; done; }
CLIP=$(curl -s --max-time 60 "https://bawazirquran.com/wp-admin/admin-ajax.php?action=bz&do=data" | python3 -c "
import json,sys
d=json.load(sys.stdin); d=d.get('data',d); r=d.get('readable',{}).get('tracks',{})
ts=[t for t in d.get('recitations',[]) if ((t.get('video') or {}).get('q')) and t.get('id') in r]
ts.sort(key=lambda t:(t.get('publishAt') or t.get('createdAt') or '', t.get('order',0)), reverse=True)
print(ts[0]['id'] if ts else '')" 2>/dev/null); echo "CLIP=$CLIP"
TID=$(curl -s --max-time 60 "https://bawazirquran.com/wp-admin/admin-ajax.php?action=bz&do=c_feed&tab=all&before=0" | tee /tmp/feed.json | python3 -c "
import json,sys
d=json.load(sys.stdin); best=[]
def walk(x):
    if isinstance(x,dict):
        if 'id' in x and 'author' in x and isinstance(x.get('id'),int): best.append(x)
        for v in x.values(): walk(v)
    elif isinstance(x,list):
        for v in x: walk(v)
walk(d)
r=[p for p in best if (p.get('replies') or 0)>0]
print((r or best)[0]['id'] if best else '')" 2>/dev/null); head -c 400 /tmp/feed.json; echo; echo "TID=$TID"
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
shots() { # $1 prefix
  for k in $KEYS; do
    adb shell am force-stop $P
    if [ "$k" = home ]; then adb shell am start -W -n $P/.MainActivity > /dev/null
    elif [ "$k" = thread ]; then timeout 40 adb shell am start -W -a android.intent.action.VIEW -d "https://bawazirquran.com/community/p/$TID" -n $P/.MainActivity > /dev/null
    elif [ "$k" = clipnav ]; then timeout 40 adb shell am start -W -n $P/.MainActivity --es open "watch/$CLIP" > /dev/null; sleep 20; for t in 1 2 3 4; do tapText "اصنع مقطع" && [ -n "$B" ] && break; adb shell input swipe 540 1500 540 800 600; sleep 2; done
    elif [ "$k" = mosques ]; then timeout 40 adb shell am start -W -n $P/.MainActivity --es open "mosques" > /dev/null; sleep 40; timeout 30 adb exec-out screencap -p > "shots/$1_mq0.png"
      tapText "انطلق إلى المسجد"; sleep 6; timeout 30 adb exec-out screencap -p > "shots/$1_mqwalk.png"; tapText "وصلت"; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_mqwalk2.png"; adb shell input keyevent 4; sleep 3
      for n in 1 2 3; do adb shell input swipe 540 1350 540 550 800; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_mq$n.png"; done
      tapText "اجعله مسجدي"; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_mqmine.png"
      adb shell input swipe 540 1350 540 550 800; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_mq4.png"
    elif [ "$k" = surahtap ]; then timeout 40 adb shell am start -W -n $P/.MainActivity --es open "\\quran" > /dev/null; sleep 20; adb shell input swipe 540 1500 540 700 700; sleep 3; tapText "سورة البقرة"; sleep 12; [ -z "$B" ] && { tapText "البقرة"; sleep 4; }
    elif [ "$k" = settingsrem ]; then setpref pmode_qiyam notify; timeout 40 adb shell am start -W -n $P/.MainActivity --es open "prayerSettings" > /dev/null; sleep 20
      for n in 1 2 3 4; do adb shell input swipe 540 1700 540 800 700; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_set$n.png"; done
    elif [ "$k" = fridayx ]; then timeout 40 adb shell am start -W -n $P/.MainActivity --es open "friday" > /dev/null; sleep 20; adb shell input swipe 540 1400 540 700 700; sleep 3; tapText "قراءة سورة الكهف"; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_fridayk.png"
      adb shell input swipe 540 1400 540 600 700; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_fridayk2.png"; adb shell input swipe 540 1400 540 600 700; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_fridayk3.png"
      tapText "اللهم صلِّ"; sleep 1; tapText "اللهم صلِّ"; sleep 2; timeout 30 adb exec-out screencap -p > "shots/$1_fridayk4.png"
    elif [ "$k" = hometab ]; then timeout 40 adb shell am start -W -n $P/.MainActivity --ez shot true --es open "home" > /dev/null; sleep 6; adb shell input swipe 540 1300 540 700 600
    elif [ "$k" = kahf ]; then timeout 40 adb shell am start -W -n $P/.MainActivity --es open "quran/18" > /dev/null
    elif [ "$k" = prayerdown ]; then timeout 40 adb shell am start -W -n $P/.MainActivity --es open "prayer" > /dev/null; sleep 18; adb shell input swipe 540 1500 540 600 700; sleep 1; adb shell input swipe 540 1500 540 600 700
    else timeout 40 adb shell am start -W -n $P/.MainActivity --es open "\\$k" > /dev/null; fi
    sleep 22; timeout 30 adb exec-out screencap -p > "shots/$1_$k.png"
    if [ "$k" = thread ]; then adb shell input swipe 540 1350 540 450 800; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_threadb.png"; fi
    if [ "$k" = clipnav ]; then
      adb shell input swipe 540 1350 540 450 800; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_clip0b.png"
      adb shell input swipe 540 1350 540 450 800; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_clip0c.png"
      adb shell input swipe 540 500 540 1400 400; sleep 1; adb shell input swipe 540 500 540 1400 400; sleep 2
      n=1; for tb in "الآيات" "شكل النص" "البيانات" "الإطار" "الحركة" "الشكل"; do tapText "$tb"; if [ -n "$B" ]; then sleep 4; timeout 30 adb exec-out screencap -p > "shots/$1_clip$n.png"; adb shell input swipe 540 1350 540 450 800; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_clip${n}b.png"; adb shell input swipe 540 1350 540 450 800; sleep 3; timeout 30 adb exec-out screencap -p > "shots/$1_clip${n}c.png"; adb shell input swipe 540 500 540 1400 400; sleep 1; adb shell input swipe 540 500 540 1400 400; sleep 2; fi; n=$((n+1)); done
    fi
    timeout 20 adb logcat -d -t 300 > "shots/log_$1_$k.txt" 2>&1; timeout 10 adb logcat -c 2>/dev/null || true
  done
}
# ---- the old version
adb install -r old.apk > shots/install_old.txt 2>&1; perms
adb shell am start -W -n $P/.MainActivity > /dev/null; sleep 25; adb exec-out screencap -p > shots/old_first.png
setpref onboarded 1; setpref lang ar; setlong lat 4629159534621622691; setlong lng 4629503834813135166
U=$(adb shell stat -c %u /data/data/$P | tr -d "\r"); adb shell "mkdir -p /data/data/$P/no_backup && touch /data/data/$P/no_backup/onboarded && chown -R $U:$U /data/data/$P/no_backup && restorecon -R /data/data/$P/no_backup"
shots old
adb shell am force-stop $P
adb shell cat /data/data/$P/shared_prefs/badr.xml > shots/old_prefs.xml
adb shell ls -laR /data/data/$P > shots/old_files.txt
# ---- the new version installed over the old one (an update: the data stays)
adb install -r new.apk > shots/install_new.txt 2>&1; perms
shots new
KEYS="hometab"; shots new
# the update's first open: «الجديد في بدر التلاوات» (and scrolled), then the same screens in the silver theme
KEYS="whatsnew"; shots new
adb shell input swipe 540 1700 540 500 700; sleep 3; timeout 30 adb exec-out screencap -p > shots/new_whatsnew2.png
adb shell input swipe 540 1700 540 500 700; sleep 3; timeout 30 adb exec-out screencap -p > shots/new_whatsnew3.png
adb shell input swipe 540 1700 540 500 700; sleep 3; timeout 30 adb exec-out screencap -p > shots/new_whatsnew4.png
adb shell input swipe 540 1700 540 500 700; sleep 3; timeout 30 adb exec-out screencap -p > shots/new_whatsnew5.png
adb shell input swipe 540 1700 540 500 700; sleep 3; timeout 30 adb exec-out screencap -p > shots/new_whatsnew6.png
setpref theme silver; KEYS="hometab"; shots silver; KEYS="whatsnew"; shots silver; adb shell input swipe 540 1700 540 500 700; sleep 3; timeout 30 adb exec-out screencap -p > shots/silver_whatsnew2.png
adb shell am force-stop $P
adb shell cat /data/data/$P/shared_prefs/badr.xml > shots/new_prefs.xml
timeout 60 adb logcat -d -b crash > shots/crash.txt 2>&1 || true
timeout 60 adb shell ls -laR /data/data/$P > shots/new_files.txt
# ---- the new version's first run (fresh install)
adb uninstall $P; adb install new.apk >/dev/null 2>&1; perms
adb shell am start -W -n $P/.MainActivity > /dev/null; sleep 25; adb exec-out screencap -p > shots/new_first.png
kill $GEO 2>/dev/null || true
ls -la shots
