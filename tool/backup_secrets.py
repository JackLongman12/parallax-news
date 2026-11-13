#!/usr/bin/env python3
"""Encrypted off-PC backup of secrets/ (signing keystore + worker admin token).

    python tool/backup_secrets.py            # writes to OneDrive\\Backups
    python tool/backup_secrets.py D:\\       # or any folder (USB stick)

Asks for a passphrase (typed twice, never shown or stored), packs secrets/
into a tar file and encrypts it with AES-256 (OpenSSL, PBKDF2, 600k rounds).
The keystore's own password is Android's public default, so this passphrase
is what actually protects it: keep it in your password manager.

Restore:
    openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in parallax-secrets-*.tar.enc -out secrets.tar
    tar -xf secrets.tar
"""
import datetime
import getpass
import io
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SECRETS = ROOT / "secrets"


def openssl():
    for c in (shutil.which("openssl"), r"C:\Program Files\Git\usr\bin\openssl.exe",
              r"C:\Program Files\Git\mingw64\bin\openssl.exe"):
        if c and pathlib.Path(c).exists():
            return c
    sys.exit("OpenSSL not found (it comes with Git for Windows).")


def main():
    if len(sys.argv) > 1:
        dest = pathlib.Path(sys.argv[1])
    else:
        dest = pathlib.Path(os.environ.get("OneDriveConsumer") or pathlib.Path.home() / "OneDrive") / "Backups"
    dest.mkdir(parents=True, exist_ok=True)
    files = [p for p in SECRETS.iterdir() if p.is_file()]
    if not files:
        sys.exit("secrets/ is empty")

    while True:
        pw = getpass.getpass("Backup passphrase (12+ characters): ")
        if len(pw) < 12:
            print("Too short, try again.")
            continue
        if getpass.getpass("Same passphrase again: ") != pw:
            print("They don't match, try again.")
            continue
        break

    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w") as tar:
        for p in files:
            tar.add(p, arcname=f"secrets/{p.name}")
    out = dest / f"parallax-secrets-{datetime.date.today():%Y-%m-%d}.tar.enc"
    env = dict(os.environ, PARALLAX_BACKUP_PW=pw)
    subprocess.run([openssl(), "enc", "-aes-256-cbc", "-pbkdf2", "-iter", "600000", "-salt",
                    "-pass", "env:PARALLAX_BACKUP_PW", "-out", str(out)],
                   input=buf.getvalue(), env=env, check=True)

    # Prove it decrypts before calling it a backup.
    check = subprocess.run([openssl(), "enc", "-d", "-aes-256-cbc", "-pbkdf2", "-iter", "600000",
                            "-pass", "env:PARALLAX_BACKUP_PW", "-in", str(out)],
                           capture_output=True, env=env, check=True).stdout
    assert check == buf.getvalue(), "verification failed"
    (dest / "parallax-secrets-RESTORE.txt").write_text(__doc__.split("Restore:")[1].strip() + "\n", encoding="utf-8")
    print(f"Encrypted backup written and verified: {out} ({len(files)} files)")


if __name__ == "__main__":
    main()
