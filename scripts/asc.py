#!/usr/bin/env python3
"""App Store Connect API helper (key from the environment): makes sure the app's bundle IDs exist (app + widgets, with App Groups)."""
import os, sys, time, json, urllib.request, urllib.error
import jwt  # pyjwt

import subprocess
KID, ISS = os.environ["ASC_KEY_ID"].strip(), os.environ["ASC_ISSUER_ID"].strip()
P8 = subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "pem.py")], capture_output=True, text=True, check=True).stdout
def token():
    now = int(time.time())
    return jwt.encode({"iss": ISS, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KID, "typ": "JWT"})
def call(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r: return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        print(method, path, e.code, e.read().decode()[:800]); return None

def ensure(ident, name):
    got = call("GET", f"/v1/bundleIds?filter[identifier]={ident}&limit=5") or {}
    hit = [d for d in got.get("data", []) if d["attributes"]["identifier"] == ident]
    if hit: bid = hit[0]["id"]; print("exists:", ident)
    else:
        r = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {"identifier": ident, "name": name, "platform": "IOS"}}})
        if not r: sys.exit(1)
        bid = r["data"]["id"]; print("registered:", ident)
    caps = call("GET", f"/v1/bundleIds/{bid}/bundleIdCapabilities") or {}
    if not any(c["attributes"]["capabilityType"] == "APP_GROUPS" for c in caps.get("data", [])):
        call("POST", "/v1/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": {"capabilityType": "APP_GROUPS"},
              "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}}); print("app groups on:", ident)

if __name__ == "__main__":
    if sys.argv[1:] == ["bundles"]:
        ensure("com.bawazirquran.app", "Badr Al-Tilawat"); ensure("com.bawazirquran.app.widgets", "Badr Al-Tilawat Widgets")
    elif sys.argv[1:] == ["devcerts"]:
        # the development certificates this workflow's runs made in the last hours (each run is a new Mac and
        # Xcode makes one per Mac; its private key leaves with the Mac). Older ones, and every distribution
        # certificate, are left alone.
        import datetime
        now = datetime.datetime.now(datetime.timezone.utc)
        got = call("GET", "/v1/certificates?limit=200") or {}
        for c in got.get("data", []):
            a = c["attributes"]
            if a.get("certificateType") not in ("DEVELOPMENT", "IOS_DEVELOPMENT"): continue
            exp = datetime.datetime.fromisoformat(a["expirationDate"].replace("Z", "+00:00"))
            made_ago = datetime.timedelta(days=365) - (exp - now)
            print("dev cert:", a.get("displayName") or a.get("name"), "made", round(made_ago.total_seconds() / 3600, 1), "h ago")
            if datetime.timedelta(0) <= made_ago < datetime.timedelta(hours=6) and "Created via API" in (a.get("name", "") + a.get("displayName", "")):
                call("DELETE", f"/v1/certificates/{c['id']}"); print("  revoked (made by an earlier run)")
    elif sys.argv[1:] == ["app"]:
        got = call("GET", "/v1/apps?filter[bundleId]=com.bawazirquran.app") or {}
        print("app record:", "found" if got.get("data") else "MISSING — create it in App Store Connect (My Apps → + → New App, bundle ID com.bawazirquran.app)")
        if not got.get("data"): sys.exit(2)
