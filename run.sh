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
setup new.apk new
pipstate() { adb shell dumpsys activity activities | grep -iE "mPictureInPicture|pinned|windowingMode=pinned" | head -5 > shots/pip_$1.txt; adb shell dumpsys window | grep -iE "pinned|PIP" | head -5 >> shots/pip_$1.txt; }
watchtest() { # $1 tag
  adb shell am force-stop $P
  timeout 40 adb shell am start -W -n $P/.MainActivity --ez shot true --es open "watch/$CLIP" > /dev/null; sleep 22
  snap ${1}_page
  rec rec_$1 60
  # the big play button sits in the middle of the video; tap the video first to show the controls if they are hidden
  adb shell input tap 540 546
  sleep 0.25; snap ${1}_tap250
  sleep 0.8; snap ${1}_tap1000
  sleep 8; snap ${1}_playing; echo "playing: $(playing)" > shots/vid_$1.txt
  adb shell input keyevent KEYCODE_HOME; sleep 4; snap ${1}_home; pipstate $1
  sleep 6; snap ${1}_home2; sleep 5; snap ${1}_home3
  endrec rec_$1
}
# the adhan stops at the first press of the power button (screen on: pressed 1 s after it starts; screen off: woken, then one press)
adhantest() { # $1 tag, $2 "off" to start with the screen off
  adb shell input keyevent KEYCODE_WAKEUP; sleep 1; adb shell wm dismiss-keyguard; sleep 1
  go home 15
  [ "$2" = off ] && { adb shell input keyevent KEYCODE_SLEEP; sleep 3; }
  adb shell am start-foreground-service -n $P/.prayer.AdhanService --es key dhuhr --es name الظهر --ez fromApp false > shots/adhan_$1_start.txt 2>&1
  sleep ${3:-1.2}; echo "before: $(playing)" > shots/adhan_$1.txt; snap adhan_$1_before
  adb shell input keyevent KEYCODE_POWER; sleep 1.5
  echo "after 1 press: $(playing)" >> shots/adhan_$1.txt
  adb shell dumpsys activity services $P/.prayer.AdhanService | grep -c ServiceRecord >> shots/adhan_$1.txt
  adb shell input keyevent KEYCODE_WAKEUP; sleep 1; adb shell wm dismiss-keyguard
}
# the opening: twice cold (the site saved), recorded — it should fade, never cut, and land on home
for n in 1 2; do
  adb shell am force-stop $P; sleep 2
  rec open$n 9; adb shell am start -n $P/.MainActivity > /dev/null; sleep 8; endrec open$n; snap open${n}_end
done
# the ayah search marks
go quranSearch 20; snap search
# the city picked by hand
go prayerSettings 20
for k in 1 2 3 4 5 6 7 8 9 10; do adb shell input swipe 540 1600 540 400 300; sleep 0.4; done; sleep 1
tapText "اختر المدينة"; sleep 2; adb shell input text "Benha"; sleep 8; snap place_search
snap place_search2
tapText "بنها" || tapText "Banha"; sleep 1; snap place_picked
tapText "حفظ"; sleep 3; adb shell cat /data/data/$P/shared_prefs/badr.xml | grep -E 'place|"cc"' > shots/place_manual.txt; snap place_saved
timeout 60 adb logcat -d > shots/logcat_all.txt 2>&1 || true
timeout 60 adb logcat -d -b crash > shots/crash.txt 2>&1 || true
kill $GEO 2>/dev/null || true
