set -x
P=com.bawazirquran.app
mkdir -p shots
adb root; sleep 3
adb shell wm size 1080x2340; adb shell wm density 440; sleep 2
( for i in $(seq 1 400); do adb emu geo fix 31.3016 30.0784 >/dev/null 2>&1; sleep 3; done ) &
GEO=$!
KEYS="#theme #lang #prayer #name #ambient #qibla #wird"
setpref() { # $1 key $2 value
  adb shell am force-stop $P
  F=/data/data/$P/shared_prefs/badr.xml
  adb shell "[ -f $F ] || echo '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?><map></map>' > $F"
  adb shell "sed -i 's#<string name=\"$1\">[^<]*</string>##; s#</map>#<string name=\"$1\">$2</string></map>#' $F"
}
setlong() { adb shell "sed -i 's#<long name=\"$1\" value=\"[^\"]*\" />##; s#</map>#<long name=\"$1\" value=\"$2\" /></map>#' /data/data/$P/shared_prefs/badr.xml"; }
perms() { for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS; do adb shell pm grant $P android.permission.$perm || true; done; }
shots() { # $1 prefix
  for k in $KEYS; do
    adb shell am force-stop $P
    if [ "$k" = home ]; then adb shell am start -W -n $P/.MainActivity > /dev/null; else adb shell am start -W -n $P/.MainActivity --es open "\\$k" > /dev/null; fi
    sleep 22; timeout 30 adb exec-out screencap -p > "shots/$1_$k.png"
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
