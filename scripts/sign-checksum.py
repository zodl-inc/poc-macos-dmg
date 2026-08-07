#!/usr/bin/env python3
"""Sign a SHA256 checksum file with Ed25519. Called from CI."""
import sys, base64, glob
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import load_pem_private_key

key_path = sys.argv[1]   # path to PEM private key
sha256_file = sys.argv[2] # path to .sha256 file

with open(key_path, "rb") as f:
    private_key = load_pem_private_key(f.read(), password=None)

with open(sha256_file, "rb") as f:
    data = f.read()

signature = private_key.sign(data)
sig_b64 = base64.b64encode(signature).decode()

out_path = sha256_file + ".sig.b64"
with open(out_path, "w") as f:
    f.write(sig_b64)

print(f"✅ Ed25519 signed {sha256_file} -> {out_path}")
print(f"   sig: {sig_b64[:40]}...")
