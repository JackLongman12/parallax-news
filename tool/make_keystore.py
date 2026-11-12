#!/usr/bin/env python3
"""Create the stable Android signing key used for every build.

Auto-update only works if every APK is signed with the SAME key, so this is
generated once, kept in `secrets/` (git-ignored) and stored as the GitHub
secret ANDROID_KEYSTORE_B64. CI installs it as ~/.android/debug.keystore
(alias androiddebugkey / password android), which Flutter's default Gradle
config already uses - no Gradle edits needed.

BACK UP secrets/signing.keystore. If it's lost, installed apps can't be
updated and every user must uninstall/reinstall.

Before a Play Store release, switch to a proper release keystore with a
strong password (or Play App Signing).
"""
import base64
import datetime
import pathlib

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

OUT = pathlib.Path(__file__).resolve().parent.parent / "secrets"


def main() -> None:
    OUT.mkdir(exist_ok=True)
    ks = OUT / "signing.keystore"
    if ks.exists():
        raise SystemExit(f"{ks} already exists - refusing to overwrite the signing key")
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Parallax News"),
                      x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Parallax News")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=365 * 30))
            .sign(key, hashes.SHA256()))
    data = pkcs12.serialize_key_and_certificates(
        b"androiddebugkey", key, cert, None,
        serialization.BestAvailableEncryption(b"android"))
    ks.write_bytes(data)
    (OUT / "signing.keystore.b64").write_text(base64.b64encode(data).decode())
    print(f"wrote {ks}")


if __name__ == "__main__":
    main()
