#!/usr/bin/env python3
"""Prints the App Store Connect key (ASC_KEY_P8) as a clean PEM, whatever way it was pasted:
on one line, with spaces, with Windows line ends, or without the BEGIN/END lines."""
import os, re, sys
raw = os.environ.get("ASC_KEY_P8", "")
body = re.sub(r"-----(BEGIN|END)[A-Z ]*-----", "", raw)
body = re.sub(r"[^A-Za-z0-9+/=]", "", body)
if len(body) < 100: sys.exit("ASC_KEY_P8 looks empty or cut — paste the whole .p8 file into the secret")
print("-----BEGIN PRIVATE KEY-----")
for i in range(0, len(body), 64): print(body[i:i + 64])
print("-----END PRIVATE KEY-----")
