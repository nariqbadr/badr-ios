set -x
P=com.bawazirquran.app
mkdir -p shots
adb root; sleep 3
adb shell wm size 1080x2340; adb shell wm density 440; sleep 2
( for i in $(seq 1 400); do adb emu geo fix 31.3016 30.0784 >/dev/null 2>&1; sleep 3; done ) &
GEO=$!
KEYS="home recitations quran adhkar community library listen mushaf"
setpref() { # $1 key $2 value
  adb shell am force-stop $P
  F=/data/data/$P/shared_prefs/badr.xml
  adb shell "[ -f $F ] || echo '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?><map></map>' > $F"
  adb shell "sed -i 's#<string name=\"$1\">[^<]*</string>##; s#</map>#<string name=\"$1\">$2</string></map>#' $F"
}
setlong() { adb shell "sed -i 's#<long name=\"$1\" value=\"[^\"]*\" />##; s#</map>#<long name=\"$1\" value=\"$2\" /></map>#' /data/data/$P/shared_prefs/badr.xml"; }
perms() { for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do adb shell pm grant $P android.permission.$perm || true; done; }
CLIP=$(curl -s --max-time 60 "https://bawazirquran.com/wp-admin/admin-ajax.php?action=bz&do=data" | python3 -c "
import json,sys
d=json.load(sys.stdin); d=d.get('data',d); r=d.get('readable',{}).get('tracks',{})
ts=[t for t in d.get('recitations',[]) if ((t.get('video') or {}).get('q')) and t.get('id') in r]
ts.sort(key=lambda t:(t.get('publishAt') or t.get('createdAt') or '', t.get('order',0)), reverse=True)
print(ts[0]['id'] if ts else '')" 2>/dev/null); echo "CLIP=$CLIP"
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
    elif [ "$k" = clipnav ]; then timeout 40 adb shell am start -W -n $P/.MainActivity --es open "watch/$CLIP" > /dev/null; sleep 20; for t in 1 2 3 4; do tapText "اصنع مقطع" && [ -n "$B" ] && break; adb shell input swipe 540 1500 540 800 600; sleep 2; done
    elif [ "$k" = prayerdown ]; then timeout 40 adb shell am start -W -n $P/.MainActivity --es open "prayer" > /dev/null; sleep 18; adb shell input swipe 540 1500 540 600 700; sleep 1; adb shell input swipe 540 1500 540 600 700
    else timeout 40 adb shell am start -W -n $P/.MainActivity --es open "\\$k" > /dev/null; fi
    sleep 22; timeout 30 adb exec-out screencap -p > "shots/$1_$k.png"
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
adb shell am force-stop $P
adb shell cat /data/data/$P/shared_prefs/badr.xml > shots/new_prefs.xml
timeout 60 adb logcat -d -b crash > shots/crash.txt 2>&1 || true
timeout 60 adb shell ls -laR /data/data/$P > shots/new_files.txt
# ---- the new version's first run (fresh install)
adb uninstall $P; adb install new.apk >/dev/null 2>&1; perms
adb shell am start -W -n $P/.MainActivity > /dev/null; sleep 25; adb exec-out screencap -p > shots/new_first.png
kill $GEO 2>/dev/null || true
ls -la shots
