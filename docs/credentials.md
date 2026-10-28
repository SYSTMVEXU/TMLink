# DWAB authorization and desktop releases

Official releases handle DWAB app authorization automatically. Users enter only
the **tournament server address, local TM API key, and OBS settings**. There is
no backend to operate and no separate app-credential file to install.

The installed executable contains a recoverable form of the shared secret.
Masking and code obfuscation discourage casual extraction; they cannot prevent a
determined recipient from recovering it. GitHub Secrets protects the originals
in the pipeline. The client ID identifies the app; the client secret needs protection.

## Configure GitHub once

Create an environment named **`dwab`** in
[repository settings](https://github.com/SYSTMVEXU/TMLink/settings/environments).
Restrict it to the default branch. Where supported by your GitHub plan and
repository visibility, require trusted reviewers and disable self-review and
administrator bypass. Protect the default branch and require review of changes
to workflows and the code they execute.

Add these **environment secrets**:

| Secret | Value |
| --- | --- |
| `VEX_TM_CLIENT_ID` | Your DWAB registration's client ID. |
| `VEX_TM_CLIENT_SECRET` | Its client secret. |
| `ATS_SYMBOLS_PASSPHRASE` | A separate, random, single-line password of at least 32 characters, generated and retained in your password manager. Never reuse the DWAB secret. |

Add this **environment variable** under Variables:

| Variable | Value for the supplied registration |
| --- | --- |
| `VEX_TM_CREDENTIAL_EXPIRES_AT` | `2027-06-08T00:00:00Z` |

The supplied registration is **Automated_Tournament_Stream**. Its credential
values do not belong in source code, issues, command arguments, or committed files.

With GitHub CLI installed and authorized to administer the environment, these
commands prompt for the secrets without putting their values in shell history.
Configure the environment restrictions in GitHub first.

```sh
gh secret set VEX_TM_CLIENT_ID --env dwab --repo SYSTMVEXU/TMLink
gh secret set VEX_TM_CLIENT_SECRET --env dwab --repo SYSTMVEXU/TMLink
gh secret set ATS_SYMBOLS_PASSPHRASE --env dwab --repo SYSTMVEXU/TMLink
gh variable set VEX_TM_CREDENTIAL_EXPIRES_AT --env dwab --repo SYSTMVEXU/TMLink --body '2027-06-08T00:00:00Z'
```

GitHub cannot return saved secrets to your local machine. Keep your own copies
in a password manager. Environment protections depend on your plan and repository visibility.

## Build and distribute

1. Update `version` in `pubspec.yaml` and merge reviewed changes into the default branch.
2. Optionally run **Actions → Check DWAB authorization** on that branch. This checks the registration without a local tournament server.
3. Run **Actions → Build desktop releases** on the default branch and approve the environment jobs if required. It analyzes and tests the app, then builds macOS, Windows x64, and Linux x64 packages.
4. Download the **ATS-macos**, **ATS-windows**, and **ATS-linux** artifacts. Extract the Actions artifact wrapper and attach the contained ZIP/tar.gz and checksum files to a GitHub Release. The workflow does not publish releases automatically.
5. Download **encrypted-symbols-…** artifacts and retain their `.gpg` files in your maintainer archive before the **30-day retention** expires. Keep the passphrase separately. Users only need the app packages.

The **Download update** button opens
<https://github.com/SYSTMVEXU/TMLink/releases/latest>, so publish maintained
releases there. macOS packages preserve app permissions and framework symlinks
and contain a universal Intel/Apple Silicon app. The workflow selects Xcode 16.4
on `macos-15` to avoid Xcode 27's multi-architecture `lipo` incompatibility with
our pinned Flutter SDK. Windows users must extract the entire ZIP, keeping the
EXE, DLLs, and data folder together. Linux needs libsecret and a running system keyring.

These packages are not Developer ID signed/notarized on macOS or publisher
signed on Windows. OS download warnings can still appear. Publisher signing
requires the corresponding certificates/accounts and is separate from DWAB authorization.

## Protection applied by the pipeline

- Only the protected release-helper step receives original credentials. Pull request CI receives none; secret-bearing workflows skip branches other than the default branch. Checkout and Flutter setup actions in those workflows are pinned to specific commits.
- The helper reads credentials and expiry into memory, creates a fresh random mask, and writes only masked bytes plus the mask to an ignored temporary build-definition file. No plaintext credential source file is generated.
- Original credentials and the symbols password are removed from child-process environments. Flutter receives the file path, without plaintext credentials on its command line. Helper output is also redacted as a backstop.
- Builds use `--release --obfuscate --split-debug-info`. Flutter obfuscation hides symbol names; separate string masking conceals credential literals. Both are reversible by recipients.
- Distribution files are scanned for UTF-8/UTF-16 plaintext credentials and recognizable debug files. This catches accidental literal exposure; it does not prove secrecy.
- Flutter and native `.pdb`, `.dSYM`, `.symbols`, and debug maps are excluded from user packages. Symbols are archived separately and encrypted using GnuPG AES-256, with the passphrase supplied through stdin. Only encrypted symbols are uploaded; the decryption password is never bundled in the app.
- Temporary definitions, staging files, and the plaintext symbol archive are removed after success/failure. The hosted workflow removes its build tree afterward. Whole build directories and package caches are not uploaded.

At runtime the DWAB pair is reconstructed in memory. OAuth tokens are cached
only in memory, renewed as needed, and never saved in settings or placed in URLs.
Bundled credentials never populate editable fields and are not copied to Keychain
when users save their server/OBS settings.

## Expiration and rotation

An update banner appears during the **30 days before expiration**. At expiration,
new TM connections fail with an update message. A rejected bundled registration
also exposes the update action. The banner is available throughout the workspace.
An approaching-expiration warning does not intentionally interrupt monitoring.
Local notices rely on the computer's clock; DWAB remains the authority on validity.

To rotate credentials, replace the two DWAB secrets and expiry variable, bump
the app version, build, and publish an update. Keep an overlap period before
retiring the old registration if DWAB permits it. Changing GitHub Secrets does
not update installed apps. Revoking a recipient's access to the shared credential
requires rotation; removing GitHub access does not invalidate an installed copy.
Prefer separate DWAB registrations per deployment when available.

## Local development and advanced overrides

Debug builds read `VEX_TM_CLIENT_ID` and `VEX_TM_CLIENT_SECRET` from the process
environment that launches Flutter. They do not use the official release bundle.
On macOS, run:

```sh
source set-credentials.sh
tool/run_debug.sh -d macos
```

`set-credentials.sh` is an optional local file ignored by Git. You can instead
export both variables in the shell before running `tool/run_debug.sh`. Finder
does not inherit terminal variables; start Debug through this script or set the
variables in your IDE's launch environment. Debug without credentials can still
use Developer mode.

Debug reads its client ID and secret from the launching process environment.
Official Release uses the masked pair supplied by the GitHub `dwab` environment.
A partial environment pair is never combined with another source. Plaintext
`--dart-define=VEX_TM_CLIENT_SECRET=…` configuration is unsupported.

Run the protected, default-branch-only **Build desktop releases** workflow with
`workflow_dispatch` to create release artifacts. Only that workflow's build step
receives the GitHub secrets; local calls to the release packager are rejected.
Artifacts appear in the workflow run and are named `ATS-macos`, `ATS-windows`,
and `ATS-linux`. The workflow does not publish a GitHub Release automatically.

Recover symbols using GnuPG's interactive password prompt:

```sh
gpg --output debug-symbols.zip --decrypt ATS-VERSION-PLATFORM-symbols.zip.gpg
```

Extract privately. Use `flutter symbolize` with the matching Flutter symbol
file; Windows x64 PDBs require a Windows debugger. Keep decrypted symbols and
the passphrase out of public issues and releases.

References: [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets),
[GitHub environments and plan availability](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments),
[Flutter obfuscation limitations and symbol handling](https://docs.flutter.dev/deployment/obfuscate).
