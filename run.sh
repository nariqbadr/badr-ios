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
setjson() { # $1 key $2 json
  adb shell am force-stop $P
  adb pull /data/data/$P/shared_prefs/badr.xml /tmp/b.xml >/dev/null 2>&1
  python3 - "$1" "$2" <<'PY'
import sys,xml.etree.ElementTree as E
t=E.parse('/tmp/b.xml'); r=t.getroot()
for e in list(r):
    if e.get('name')==sys.argv[1]: r.remove(e)
s=E.SubElement(r,'string',name=sys.argv[1]); s.text=sys.argv[2]
t.write('/tmp/b.xml',encoding='utf-8',xml_declaration=True)
PY
  adb push /tmp/b.xml /data/data/$P/shared_prefs/badr.xml >/dev/null
  U=$(adb shell stat -c %u /data/data/$P | tr -d "\r"); adb shell "chown $U:$U /data/data/$P/shared_prefs/badr.xml; restorecon /data/data/$P/shared_prefs/badr.xml"
}
setup new.apk new
dump() { timeout 30 adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; timeout 30 adb pull /sdcard/ui.xml shots/$1.xml >/dev/null 2>&1; cp shots/$1.xml /tmp/ui.xml 2>/dev/null; }
center() { python3 - "$1" "$2" <<'PY2'
import re,sys
x=open(sys.argv[1],encoding='utf-8').read()
for m in re.finditer(r'<node [^>]*>', x):
    n=m.group(0)
    if re.search(sys.argv[2], n):
        b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
        if b:
            a=list(map(int,b.groups())); print((a[0]+a[2])//2,(a[1]+a[3])//2); break
PY2
}
go home 20
for attempt in 1 2 3; do
  go widgets 12
  tapText "أضف للشاشة"; sleep 8; dump pin; snap pin
  B=$(center shots/pin.xml 'text="(Add to home screen|إضافة إلى الشاشة الرئيسية)"'); echo "pin add -> $B" >> shots/runs.txt
  [ -n "$B" ] && adb shell input tap $B
  sleep 6; adb shell input keyevent 3; sleep 6; dump home; snap home
  W=$(center shots/home.xml 'class="com.android.launcher3.widget.LauncherAppWidgetHostView"|class="android.widget.ImageView"[^>]*content-desc="مواقيت الصلاة"'); grep -q 'text="الويدجت"' shots/home.xml && W=""; echo "widget -> $W" >> shots/runs.txt
  [ -n "$W" ] && break
done
if [ -n "$W" ]; then
  adb shell input swipe $W $W 1600; sleep 2; dump press; snap press
  R=$(center shots/press.xml 'content-desc="[^"]*(Change widget settings|Reconfigure|إعادة ضبط|Customize|تخصيص|Widget settings|إعدادات الأداة|إعدادات التطبيق المصغّر)[^"]*"|text="(Reconfigure|إعادة ضبط|Customize|تخصيص)"'); echo "reconfigure -> $R" >> shots/runs.txt
  if [ -n "$R" ]; then
    adb shell input tap $R; sleep 5; dump cfg; snap cfg
    adb shell input tap 300 1150; sleep 3; snap cfg2
    tapText 'text="تم"'; sleep 3; adb shell input keyevent 3; sleep 6; snap home2; dump home2
    grep -c 'content-desc="مواقيت الصلاة"' shots/home2.xml | sed 's/^/widget after تم: /' >> shots/runs.txt
    sleep 20; snap home3
  fi
fi
timeout 60 adb logcat -d -b crash > shots/crash.txt 2>&1 || true
timeout 60 adb logcat -d 2>/dev/null | grep -i -E 'BadrWidget|appwidget|RemoteViews|TransactionTooLarge' | grep -v -i 'chrome' | tail -150 > shots/widgetlog.txt || true
kill $GEO 2>/dev/null || true
