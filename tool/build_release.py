#!/usr/bin/env python3
"""Build desktop releases with concealed DWAB strings and encrypted symbols.

Uses Python's standard library, Flutter, and GnuPG. This is reversible string
obfuscation, not a way to keep a shared secret from the owner of an executable.
"""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import mmap
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
SECRET_NAMES = ("VEX_TM_CLIENT_ID", "VEX_TM_CLIENT_SECRET", "ATS_SYMBOLS_PASSPHRASE")


class ReleaseError(Exception):
    """Only sanitized messages should be used here."""


def credential_defines(environment, now=None):
    client_id = environment.get("VEX_TM_CLIENT_ID", "")
    secret = environment.get("VEX_TM_CLIENT_SECRET", "")
    if not client_id or not secret:
        raise ReleaseError("Set both DWAB client credential environment variables.")
    try:
        expiry = datetime.fromisoformat(environment["VEX_TM_CREDENTIAL_EXPIRES_AT"].replace("Z", "+00:00"))
        if expiry.tzinfo is None:
            raise ValueError()
        expiry = expiry.astimezone(timezone.utc)
    except (KeyError, ValueError):
        raise ReleaseError("Set VEX_TM_CREDENTIAL_EXPIRES_AT to an ISO 8601 date with timezone.") from None
    if expiry <= (now or datetime.now(timezone.utc)):
        raise ReleaseError("DWAB credentials have expired. Replace them before building.")
    data = json.dumps({
        "version": 1, "clientId": client_id, "clientSecret": secret,
        "expiresAt": expiry.isoformat().replace("+00:00", "Z"),
    }, separators=(",", ":"), ensure_ascii=False).encode()
    mask = secrets.token_bytes(len(data))
    payload = bytes(a ^ b for a, b in zip(data, mask))
    return {
        "TMLINK_CREDENTIAL_PAYLOAD": base64.b64encode(payload).decode(),
        "TMLINK_CREDENTIAL_MASK": base64.b64encode(mask).decode(),
        "TMLINK_RELEASE_BUILD": "true",
    }, expiry


def child_environment(environment):
    """Build tools and packaging processes do not need the original secrets."""
    return {k: v for k, v in environment.items() if k not in SECRET_NAMES}


def run(command, environment, private_values=(), stdin=None):
    result = subprocess.run(
        [str(arg) for arg in command], cwd=ROOT, env=environment,
        input=stdin, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    output = result.stdout.decode(errors="replace")
    for value in private_values:
        if value:
            output = output.replace(value, "[redacted]")
    if output.strip():
        print(output, end="" if output.endswith("\n") else "\n", flush=True)
    if result.returncode:
        raise ReleaseError("A release build or packaging step failed; see the sanitized output above.")


def is_debug_file(path):
    return any(
        part.lower().endswith((".pdb", ".dsym", ".symbols", ".map.json", ".debug"))
        for part in Path(path).parts
    )


def scan_distribution(directory, values):
    """Fail if either raw credential appears as a UTF-8/UTF-16 literal."""
    patterns = [value.encode(encoding) for value in values for encoding in ("utf-8", "utf-16-le")]
    for path in directory.rglob("*"):
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            continue
        with path.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
            if any(data.find(pattern) >= 0 for pattern in patterns):
                raise ReleaseError("A raw credential was found in the distribution. Packaging was stopped.")
        if is_debug_file(path.relative_to(directory)):
            raise ReleaseError("Debug symbols were found in the distribution. Packaging was stopped.")


def encrypt_symbols(source_zip, destination, passphrase, environment, gpg, home):
    if len(passphrase) < 32 or "\n" in passphrase or "\r" in passphrase:
        raise ReleaseError("Use a single-line ATS_SYMBOLS_PASSPHRASE of at least 32 characters.")
    home.mkdir(mode=0o700)
    run([
        gpg, "--homedir", home, "--batch", "--yes", "--no-symkey-cache",
        "--pinentry-mode", "loopback", "--passphrase-fd", "0",
        "--symmetric", "--cipher-algo", "AES256", "--output", destination, source_zip,
    ], environment, (passphrase,), stdin=(passphrase + "\n").encode())


def build(target):
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise ReleaseError("Official release builds must run through GitHub Actions.")
    expected_host = {"macos": "darwin", "windows": "win32", "linux": "linux"}[target]
    if sys.platform != expected_host:
        raise ReleaseError("Build each desktop target on its corresponding operating system.")
    environment = dict(os.environ)
    defines, expiry = credential_defines(environment)
    passphrase = environment.get("ATS_SYMBOLS_PASSPHRASE", "")
    if len(passphrase) < 32 or "\n" in passphrase or "\r" in passphrase:
        raise ReleaseError("Set a single-line ATS_SYMBOLS_PASSPHRASE of at least 32 characters.")
    flutter = shutil.which("flutter")
    gpg = shutil.which("gpg")
    if not gpg and sys.platform == "win32":
        bundled_gpg = Path(environment.get("ProgramFiles", r"C:\Program Files")) / "Git/usr/bin/gpg.exe"
        if bundled_gpg.is_file():
            gpg = str(bundled_gpg)
    if not flutter or not gpg:
        raise ReleaseError("Install Flutter and GnuPG and make them available on PATH.")
    version_match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?)\s*$", (ROOT / "pubspec.yaml").read_text(), re.M)
    if not version_match:
        raise ReleaseError("Set a numeric release version in pubspec.yaml before building.")
    version = version_match.group(1)
    label = target
    if target == "macos" and environment.get("FLUTTER_XCODE_ARCHS"):
        arch = environment["FLUTTER_XCODE_ARCHS"]
        if arch not in ("arm64", "x86_64"):
            raise ReleaseError("For a single-architecture macOS build, choose arm64 or x86_64.")
        label += "-" + arch
    name = f"ATS-{version}-{label}"
    build_dir = ROOT / "build"
    build_dir.mkdir(exist_ok=True)
    public_dir = build_dir / "distributions"
    private_dir = build_dir / "private-symbols"
    public_dir.mkdir(exist_ok=True)
    private_dir.mkdir(exist_ok=True)
    package = public_dir / (name + (".tar.gz" if target == "linux" else ".zip"))
    encrypted = private_dir / (name + "-symbols.zip.gpg")
    checksum = public_dir / (package.name + ".sha256")
    outputs = (package, encrypted, checksum)
    for path in outputs:
        path.unlink(missing_ok=True)
    success = False
    try:
        with tempfile.TemporaryDirectory(prefix="release-private-", dir=build_dir) as scratch:
            work = Path(scratch)
            definitions = work / "defines.json"
            definitions.write_text(json.dumps(defines))
            definitions.chmod(0o600)
            env = child_environment(environment)
            sensitive = tuple(environment.get(key, "") for key in SECRET_NAMES)
            symbols = work / "symbols"
            print(f"Building {name}; DWAB authorization expires {expiry.date()} UTC.", flush=True)
            run([
                flutter, "build", target, "--release", "--obfuscate",
                f"--split-debug-info={symbols}", f"--dart-define-from-file={definitions}",
            ], env, sensitive)
            if not symbols.is_dir() or not any(symbols.rglob("*")):
                raise ReleaseError("Flutter did not produce split debug symbols. No package was published.")
            source = ROOT / {
                "macos": "build/macos/Build/Products/Release/ATS.app",
                "windows": "build/windows/x64/runner/Release",
                "linux": "build/linux/x64/release/bundle",
            }[target]
            if not source.is_dir():
                raise ReleaseError("The expected Flutter release bundle is missing.")
            # Archive native symbols separately, too. Do not include old build
            # definitions, build trees, or arbitrary files from the workspace.
            native_root = source.parent if target == "macos" else source
            for debug_path in native_root.rglob("*"):
                if debug_path.suffix.lower() == ".pdb" and debug_path.is_file():
                    dest = symbols / "native" / debug_path.relative_to(native_root)
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(debug_path, dest)
                elif debug_path.name.endswith(".dSYM") and debug_path.is_dir():
                    dest = symbols / "native" / debug_path.relative_to(native_root)
                    shutil.copytree(debug_path, dest, dirs_exist_ok=True)
            staging = work / name
            bundle = staging / source.name if target == "macos" else staging
            shutil.copytree(source, bundle, symlinks=True, ignore=lambda _, names: [n for n in names if is_debug_file(n)])
            instructions = (
                "Automated Tournament Stream (ATS)\n\n"
                "macOS: move ATS.app to Applications, then open it.\n"
                "Windows: extract the entire ZIP, then open tmlink.exe. Keep its other files together.\n"
                "Linux: extract the archive and open tmlink; a system keyring and libsecret are required.\n\n"
                "Open Connections and enter your tournament server address, its TM API key, and OBS settings.\n"
                "App authorization is automatic; no app client credentials need to be entered.\n"
                "Updates: https://github.com/SYSTMVEXU/TMLink/releases/latest\n"
            )
            (staging / "START HERE.txt").write_text(instructions)
            (staging / "release-info.json").write_text(json.dumps({
                "version": version, "platform": label, "credentialsExpireAt": expiry.isoformat(),
                "commit": environment.get("GITHUB_SHA", "local"),
            }, indent=2))
            scan_distribution(staging, (environment["VEX_TM_CLIENT_ID"], environment["VEX_TM_CLIENT_SECRET"]))
            if target == "macos":
                # ditto preserves framework symlinks, executable modes and app metadata.
                run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", staging, package], env, sensitive)
            elif target == "linux":
                with tarfile.open(package, "w:gz") as archive:
                    archive.add(staging, arcname=name)
            else:
                shutil.make_archive(str(package.with_suffix("")), "zip", staging)
            (symbols / "release-info.json").write_text((staging / "release-info.json").read_text())
            symbol_zip = Path(shutil.make_archive(str(work / "debug-symbols"), "zip", symbols))
            encrypt_symbols(symbol_zip, encrypted, passphrase, env, gpg, work / "gnupg")
            with package.open("rb") as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            checksum.write_text(f"{digest}  {package.name}\n")
            success = True
    finally:
        if not success:
            for path in outputs:
                path.unlink(missing_ok=True)
    print(f"Release package: {package.relative_to(ROOT)}")
    print(f"Encrypted symbols: {encrypted.relative_to(ROOT)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", choices=("macos", "windows", "linux"))
    args = parser.parse_args()
    try:
        build(args.target)
    except ReleaseError as error:
        print(f"Release stopped: {error}", file=sys.stderr)
        return 1
    except Exception:
        # Unexpected exceptions can contain process arguments or credential data.
        print("Release stopped due to an unexpected build or filesystem error.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
