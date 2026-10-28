import base64
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from build_release import (
    ReleaseError, child_environment, credential_defines, encrypt_symbols,
    gnupg_command, is_debug_file, scan_distribution, stop_gpg_agent,
)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.environment = {
            "VEX_TM_CLIENT_ID": "synthetic-client-for-release-tests",
            "VEX_TM_CLIENT_SECRET": "synthetic-secret-for-release-tests",
            "VEX_TM_CREDENTIAL_EXPIRES_AT": "2099-06-08T00:00:00Z",
            "ATS_SYMBOLS_PASSPHRASE": "synthetic-symbol-passphrase-for-tests-only",
            "PATH": os.environ.get("PATH", ""),
        }

    def test_masks_are_random_and_plaintext_is_absent_from_definitions(self):
        first, expiry = credential_defines(self.environment)
        second, _ = credential_defines(self.environment)
        self.assertNotEqual(first, second)
        encoded = json.dumps(first)
        self.assertNotIn(self.environment["VEX_TM_CLIENT_ID"], encoded)
        self.assertNotIn(self.environment["VEX_TM_CLIENT_SECRET"], encoded)
        data = base64.b64decode(first["TMLINK_CREDENTIAL_PAYLOAD"])
        mask = base64.b64decode(first["TMLINK_CREDENTIAL_MASK"])
        decoded = json.loads(bytes(a ^ b for a, b in zip(data, mask)))
        self.assertEqual(decoded["clientId"], self.environment["VEX_TM_CLIENT_ID"])
        self.assertEqual(decoded["clientSecret"], self.environment["VEX_TM_CLIENT_SECRET"])
        self.assertEqual(decoded["expiresAt"], "2099-06-08T00:00:00Z")
        self.assertEqual(expiry.tzinfo, timezone.utc)

    def test_missing_invalid_or_expired_configuration_fails_closed(self):
        for key in ("VEX_TM_CLIENT_ID", "VEX_TM_CLIENT_SECRET", "VEX_TM_CREDENTIAL_EXPIRES_AT"):
            env = dict(self.environment)
            del env[key]
            with self.assertRaises(ReleaseError):
                credential_defines(env)
        for value in ("invalid", "2099-06-08", "2020-06-08T00:00:00Z"):
            env = dict(self.environment, VEX_TM_CREDENTIAL_EXPIRES_AT=value)
            with self.assertRaises(ReleaseError):
                credential_defines(env)
        with self.assertRaises(ReleaseError):
            credential_defines(self.environment, now=datetime(2099, 6, 8, tzinfo=timezone.utc))

    def test_build_processes_do_not_inherit_original_secrets(self):
        env = child_environment(self.environment)
        self.assertEqual(env["PATH"], self.environment["PATH"])
        self.assertNotIn("VEX_TM_CLIENT_SECRET", env)
        self.assertNotIn("VEX_TM_CLIENT_ID", env)
        self.assertNotIn("ATS_SYMBOLS_PASSPHRASE", env)

    def test_distribution_rejects_plaintext_and_debug_symbols(self):
        for name in ("app.pdb", "App.dSYM/Contents/DWARF/App", "app.symbols", "app.map.json"):
            self.assertTrue(is_debug_file(name))
        self.assertFalse(is_debug_file("data/app.so"))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / "app.bin"
            binary.write_bytes(b"safe content")
            scan_distribution(root, ("synthetic-client", "synthetic-secret"))
            for encoding in ("utf-8", "utf-16-le"):
                binary.write_bytes("synthetic-secret".encode(encoding))
                with self.assertRaises(ReleaseError):
                    scan_distribution(root, ("synthetic-client", "synthetic-secret"))
            binary.unlink()
            (root / "app.pdb").write_bytes(b"private symbols")
            with self.assertRaises(ReleaseError):
                scan_distribution(root, ("synthetic-client", "synthetic-secret"))

    @unittest.skipUnless(shutil.which("gpg"), "GnuPG is required for the encryption integration check")
    def test_symbols_can_only_be_decrypted_with_the_maintainer_passphrase(self):
        with tempfile.TemporaryDirectory(prefix="ats symbols test ") as directory:
            root = Path(directory)
            source = root / "symbols.zip"
            source.write_bytes(b"synthetic-private-debug-symbols")
            encrypted = root / "symbols.zip.gpg"
            env = child_environment(dict(os.environ))
            password = self.environment["ATS_SYMBOLS_PASSPHRASE"]
            home = root / "gnupg"
            gpg = shutil.which("gpg")
            try:
                encrypt_symbols(source, encrypted, password, env, gpg, home)
                self.assertNotIn(source.read_bytes(), encrypted.read_bytes())
                command = gnupg_command(gpg, [
                    "--homedir", home, "--batch", "--no-symkey-cache",
                    "--pinentry-mode", "loopback", "--passphrase-fd", "0",
                    "--decrypt", encrypted,
                ], env)
                failed = subprocess.run(command, input=b"wrong-passphrase\n", capture_output=True, env=env)
                self.assertNotEqual(failed.returncode, 0)
                result = subprocess.run(command, input=(password + "\n").encode(), capture_output=True, env=env)
                self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
                self.assertEqual(result.stdout, source.read_bytes())
            finally:
                stop_gpg_agent(gpg, home, env)


if __name__ == "__main__":
    unittest.main()
