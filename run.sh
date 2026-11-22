set -x
P=com.bawazirquran.app
mkdir -p shots
adb install -r app.apk > shots/install.txt 2>&1
for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do adb shell pm grant $P android.permission.$perm || true; done
( for i in $(seq 1 600); do adb emu geo fix 31.3016 30.0784 >/dev/null 2>&1; sleep 3; done ) &
GEO=$!
sleep 5
go() { adb shell am force-stop $P; adb shell am start -W -n $P/.MainActivity --ez shot true --es open "$2" > /dev/null; sleep "$3"; adb exec-out screencap -p > "shots/$1.png"; }
go intro intro 4
adb exec-out screencap -p > shots/intro2.png
go home home 45
go maker maker 25
go makervideo makervideo 70
adb exec-out screencap -p > shots/makervideo2.png; sleep 150; adb exec-out screencap -p > shots/makervideo3.png
go clip clip 30
go clipsave clipsave 90
adb exec-out screencap -p > shots/clipsave2.png; sleep 90; adb exec-out screencap -p > shots/clipsave3.png
adb shell run-as $P ls -la cache/maker-out > shots/out.txt 2>&1
for f in $(adb shell run-as $P ls cache/maker-out | tr -d '\r'); do adb exec-out run-as $P cat "cache/maker-out/$f" > "shots/$f"; done
adb shell input swipe 540 1800 540 600 400; sleep 3; adb exec-out screencap -p > shots/home2.png
adb shell input swipe 540 1800 540 300 400; sleep 3; adb exec-out screencap -p > shots/home3.png
go recitations recitations 30
go prayer prayer 30
go adhkar adhkar 20
go library library 20
go drawer drawer 25
go theme theme 25
go player player 35
go reciter reciter 30
go search search 20
go prayerSettings prayerSettings 25
go listen listen 25
go watch watch 35
go community community 30
go read read 25
go readtrack readtrack 35
go widgets widgets 30
adb logcat -d -b crash > shots/crash.txt 2>&1 || true
adb logcat -d | grep -iE "bawazir|AndroidRuntime|FATAL" | tail -300 > shots/log.txt 2>&1 || true
kill $GEO 2>/dev/null || true
ls -la shots
