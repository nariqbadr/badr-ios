set -x
P=com.bawazirquran.app
mkdir -p shots
adb root; sleep 3
adb shell wm size 1080x2340; adb shell wm density 440; sleep 2
( for i in $(seq 1 400); do adb emu geo fix 31.3016 30.0784 >/dev/null 2>&1; sleep 3; done ) &
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

# ---- 2.10.89 as people have it, then the update over it
adb install -r old.apk > shots/install_old.txt 2>&1; perms
adb shell am start -W -n $P/.MainActivity > /dev/null; sleep 25
setpref onboarded 1; setpref lang ar; setlong lat 4629159534621622691; setlong lng 4629503834813135166
U=$(adb shell stat -c %u /data/data/$P | tr -d "\r"); adb shell "mkdir -p /data/data/$P/no_backup && touch /data/data/$P/no_backup/onboarded && chown -R $U:$U /data/data/$P/no_backup && restorecon -R /data/data/$P/no_backup"
adb shell am force-stop $P
adb install -r new.apk > shots/install_new.txt 2>&1; perms
adb logcat -c

# ---- 1: the first open after the update: intro → What's New → its posters → «متابعة» → home (duha / qiyam)
rec tour1 170
adb shell am start -n $P/.MainActivity > /dev/null; sleep 12; snap wn
adb shell input swipe 540 1500 540 1000 900; sleep 2
adb shell input swipe 150 950 950 950 500; sleep 2; adb shell input swipe 150 950 950 950 500; sleep 2; snap wnrow
for n in 1 2 3 4 5 6 7 8 9 10; do up 1.2; done
tapText "متابعة"; sleep 4; snap home
up 2; up 2; snap home2; down 1; down 1
endrec tour1

# ---- 2: the mushaf and its search (a surah by number), the surah index opening the mushaf, the ayah search
rec tour2 170
tapText "المصحف"; sleep 6; snap quran
up 1.5; tapText "سورة النساء"; sleep 7; snap kahfmushaf
tapText "ابحث عن سورة أو آية وانتقل"; sleep 3; adb shell input text 36; sleep 3; snap msearch
tapText "سورة يس"; sleep 6; snap yasin
tapText "المصحف"; sleep 3
timeout 40 adb shell am start -W -n $P/.MainActivity --es open "quranSearch" > /dev/null; sleep 8; snap ayahsearch
up 2; snap ayahsearch2
tapText "سورة طه"; sleep 7; snap taha
adb shell input keyevent 4; sleep 2
endrec tour2

# ---- 3: the adhkar (the card, counting), «سنن يوم الجمعة», «فضائل يوم الجمعة»
rec tour3 170
tapText "الأذكار"; sleep 5; snap adhkar
for n in 1 2 3; do tapText "اضغط للعد"; sleep 0.6; done; sleep 1
adb shell input swipe 900 1000 150 1000 400; sleep 2; adb shell input swipe 900 1000 150 1000 400; sleep 2; snap adhkar2
tapText "سنن يوم الجمعة"; sleep 4; snap friday
tapText "قراءة سورة الكهف"; sleep 2; up 2; snap friday2; up 2; up 2
tapText "فضائل يوم الجمعة"; sleep 4; snap fadail; up 2; up 2; snap fadail2
adb shell input keyevent 4; sleep 2
endrec tour3

# ---- 4: the prayer page, its settings (reminders, the voices, «تجربة الإشعار»), the notification opening the whole recording
rec tour4 170
tapText "الرئيسية"; sleep 3
timeout 40 adb shell am start -W -n $P/.MainActivity --es open "prayer" > /dev/null; sleep 6; snap prayer
up 2; up 2; snap prayer2
timeout 40 adb shell am start -W -n $P/.MainActivity --es open "prayerSettings" > /dev/null; sleep 5
for n in 1 2 3 4; do up 1.5; done; snap settings
tapText "استماع"; sleep 4; snap listen; tapText "إيقاف"; sleep 1
tapText "تجربة الإشعار"; sleep 3; snap tested
adb shell cmd statusbar expand-notifications; sleep 3; snap shade
tapText "صلِّ على محمد"; sleep 6; snap voice
sleep 8; adb shell input keyevent 4; sleep 2
endrec tour4

# ---- 5: the rain sound, then the app swiped away: nothing keeps sounding
rec tour5 120
timeout 40 adb shell am start -W -n $P/.MainActivity --es open "#ambient" > /dev/null; sleep 5; tapText "مطر"; sleep 5; snap rain
echo "rain playing: $(playing)" > shots/swipe.txt
adb shell input keyevent KEYCODE_BACK; sleep 1
adb shell input keyevent KEYCODE_APP_SWITCH; sleep 3; snap recents
adb shell input swipe 540 1000 540 100 200; sleep 5
echo "after swipe: $(playing)" >> shots/swipe.txt
adb shell input keyevent KEYCODE_HOME; sleep 3
endrec tour5

timeout 60 adb logcat -d -b crash > shots/crash.txt 2>&1 || true
timeout 60 adb logcat -d | grep -iE "ANR in|FATAL|Choreographer.*Skipped [0-9]{3,}" > shots/anr.txt 2>&1 || true
kill $GEO 2>/dev/null || true
ls -la shots
