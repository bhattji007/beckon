# Distributing Beckon

How a build on your Mac becomes a download that strangers' Macs will open without a fight.
Everything here is owned by you (the account holder); the other engineer's code under `app/` is
untouched by it.

```
app/build.sh ──▶ release/release.sh ──▶ dist/Beckon-<v>.dmg + .zip + appcast.json
                     │  sign (Developer ID, hardened runtime)
                     │  notarize (notarytool) + staple
                     └─ GitHub Actions does the same on `git push --tags`
site/ ──▶ beckon.shubham.club  (landing page, /latest/Beckon.dmg, /appcast.json)
```

Prerequisites: macOS 14+, Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not
required for the build, but `notarytool`/`stapler` come with the Command Line Tools since Xcode 13.

---

## 1. Join the Apple Developer Program (one time, 99 USD/year)

1. Go to <https://developer.apple.com/programs/enroll/> and sign in with the Apple ID you want to
   own the certificates (use a personal Apple ID you will keep; it can differ from your iCloud one).
2. Enroll as an **Individual** (fastest; your legal name appears in the certificate as
   `Developer ID Application: Shubham Bhatt (TEAMID)`) or as an Organisation (needs a D-U-N-S number
   and takes days). Individual is fine for Beckon.
3. Pay. Activation takes from minutes to ~48 h. You will know it is done when
   <https://developer.apple.com/account> shows *Certificates, Identifiers & Profiles*.
4. Note your **Team ID** (10 characters, Membership details page). You will need it later.

Without the program you can still run `release/release.sh`: it produces an ad-hoc signed app that
works on your own Mac but shows the "cannot be verified" dialog on every other Mac (see §9).

## 2. Create the Developer ID Application certificate

Developer ID is the certificate type for apps distributed *outside* the Mac App Store. Apple limits
you to a handful of them, and they cannot be re-downloaded with the private key, so back it up (§3).

Easiest path, with Xcode installed:

1. Xcode → Settings → Accounts → add your Apple ID → select the team → **Manage Certificates…**
2. Click **+** → **Developer ID Application**. Xcode creates the key in your login keychain and
   uploads the CSR for you.

Without Xcode, by hand:

1. Keychain Access → Certificate Assistant → **Request a Certificate From a Certificate Authority…**
   Enter your email, Common Name e.g. `Beckon Developer ID`, choose *Saved to disk*. This creates a
   private key in the login keychain and a `.certSigningRequest` file.
2. <https://developer.apple.com/account/resources/certificates/add> → **Developer ID Application**
   → *G2 Sub-CA (Xcode 11.4.1 or later)* → upload the CSR → download `developerID_application.cer`.
3. Double-click the `.cer` to add it to the login keychain. It pairs with the private key from step 1.
4. If `codesign` later says the certificate is "not trusted", install Apple's intermediate
   *Developer ID - G2* certificate from <https://www.apple.com/certificateauthority/>.

Verify:

```sh
security find-identity -v -p codesigning
#  1) ABCDEF0123456789… "Developer ID Application: Your Name (TEAMID)"
```

Copy the quoted string exactly; that is `BECKON_SIGN_IDENTITY`.

## 3. Export the certificate + key as a .p12 (backup and CI)

1. Keychain Access → *login* keychain → category *My Certificates* → find
   **Developer ID Application: …** → expand the arrow so the private key shows → select **both**
   rows → right-click → **Export 2 items…** → format *Personal Information Exchange (.p12)*.
2. Choose a strong password. You will store it as a secret; you do not need to remember it.
3. Keep the `.p12` in your password manager. Never commit it (`.gitignore` already ignores `*.p12`).
4. For GitHub Actions, base64-encode it for the secret:

   ```sh
   base64 -i Certificates.p12 | pbcopy      # → secret BECKON_P12_BASE64
   ```

   and store the export password as `BECKON_P12_PASSWORD`.

## 4. Notarization credentials (notarytool)

Notarization is Apple scanning your binary and issuing a "ticket"; Gatekeeper on macOS 10.15+
refuses Developer-ID apps that lack one. `release.sh` uses `xcrun notarytool` with a stored keychain
profile so no secret appears on the command line.

**Recommended: App Store Connect API key** (works for CI, no 2FA prompts).

1. <https://appstoreconnect.apple.com/access/integrations/api> → *Team Keys* → **+**. Name it
   `beckon-notary`, role **Developer** (Admin also works). Download `AuthKey_XXXXXXXXXX.p8`
   *once*; Apple will not offer it again.
2. Note the **Key ID** (file name suffix) and the **Issuer ID** (UUID at the top of the page).
3. Store the profile on your Mac:

   ```sh
   xcrun notarytool store-credentials beckon \
     --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer 00000000-0000-0000-0000-000000000000
   ```

   The profile name (`beckon`) is `BECKON_NOTARY_PROFILE`. Check it with
   `xcrun notarytool history --keychain-profile beckon`.

**Alternative: Apple ID + app-specific password.** Create one at <https://account.apple.com> →
Sign-In and Security → App-Specific Passwords, then:

```sh
xcrun notarytool store-credentials beckon --apple-id you@example.com --team-id TEAMID --password xxxx-xxxx-xxxx-xxxx
```

For GitHub Actions, store the `.p8` **contents** as `BECKON_NOTARY_KEY_P8` (`cat AuthKey_*.p8 | pbcopy`),
plus `BECKON_NOTARY_KEY_ID` and `BECKON_NOTARY_ISSUER_ID`. The workflow creates the keychain profile itself.

## 5. Environment variables

| Variable | Required for | Example |
|---|---|---|
| `BECKON_SIGN_IDENTITY` | Developer ID signing | `Developer ID Application: Your Name (TEAMID)` |
| `BECKON_NOTARY_PROFILE` | notarization | `beckon` |
| `BECKON_NOTARY_KEYCHAIN` | only if the profile is in a non-default keychain (CI) | `/path/to/x.keychain-db` |
| `BECKON_DOWNLOAD_BASE` | where the dmg will be hosted; goes into `appcast.json` | default `https://beckon.shubham.club/releases` |
| `BECKON_SKIP_BUILD` | reuse `app/build/Beckon.app` | `1` |

Put the first two in your shell profile (they are not secrets; the key material lives in the keychain):

```sh
export BECKON_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export BECKON_NOTARY_PROFILE=beckon
```

## 6. Cut a release locally

1. Bump `CFBundleShortVersionString` in `app/Info.plist` (semver, e.g. `0.9.0`) and bump
   `CFBundleVersion` (any increasing integer). The other engineer owns that file; coordinate.
2. Write the user-facing notes in `release/NOTES.md` (Markdown; it becomes `notes` in `appcast.json`
   and the GitHub release body).
3. Run:

   ```sh
   release/release.sh
   ```

   It builds (`app/build.sh`), copies the app to `dist/.stage`, signs inside-out with hardened
   runtime + secure timestamp + `release/Beckon.entitlements` (an empty dict: a non-sandboxed
   menu-bar app needs no exceptions), submits the app for notarization, staples it, zips it
   (`ditto -c -k --keepParent`), builds `Beckon-<v>.dmg` (volume "Beckon <v>", with an
   `/Applications` symlink), notarizes and staples the dmg, runs `spctl --assess`, writes
   `appcast.json`, `_redirects` and `SHA256SUMS.txt`. Re-running overwrites everything; nothing
   under `app/` is modified.
4. Expect ~2–10 minutes for the two notarization round-trips. On failure the script prints the
   notary log, which names the offending file and reason.
5. Sanity-check on a *different* user account or Mac: download the dmg through a browser (so it
   gets the quarantine flag), open it, drag to Applications, launch. It must open with no dialog.

Local-only check without any certificate: `release/release.sh` with no env vars set builds an
ad-hoc signed dmg/zip and prints a loud warning. Use it to test the packaging, never publish it.

## 7. Tag a release (GitHub Actions)

The workflow `.github/workflows/release.yml` runs on every `v*` tag on a `macos-15` runner:
imports the `.p12` into a temporary keychain, stores the notary profile, runs `release/release.sh`,
uploads `dist/*` as a build artifact and attaches the dmg/zip/appcast/checksums to a GitHub
release. If the secrets are missing it still builds and publishes an **unsigned** artifact with a
warning in the release notes, so the pipeline can be tried before the Apple paperwork is done.

Add the secrets once (repo → Settings → Secrets and variables → Actions):
`BECKON_P12_BASE64`, `BECKON_P12_PASSWORD`, `BECKON_NOTARY_KEY_P8`, `BECKON_NOTARY_KEY_ID`,
`BECKON_NOTARY_ISSUER_ID`. Optionally the variable `BECKON_DOWNLOAD_BASE`.

Then:

```sh
git commit -am "Beckon 0.9.0"
git tag v0.9.0            # must equal CFBundleShortVersionString; the workflow fails otherwise
git push && git push --tags
```

A tag with a hyphen (`v0.9.0-beta.1`) is published as a pre-release. `workflow_dispatch` runs the
build without publishing a release (artifact only).

## 8. Publish to the site

`site/` is the whole website (see `site/README.md`). After a release:

```sh
mkdir -p site/releases
cp dist/Beckon-*.dmg dist/Beckon-*.zip site/releases/
cp dist/appcast.json dist/_redirects site/
```

Commit and push (git-connected Cloudflare Pages) or `wrangler pages deploy site`. The Download
button links to `/latest/Beckon.dmg`, which `_redirects` points at the newest versioned file; the
app's update checker reads `/appcast.json` (`BeckonUpdateFeedURL` in Info.plist must be
`https://beckon.shubham.club/appcast.json`). Old versioned files stay in `releases/` so existing
appcasts and links never break.

Checklist after deploying: `curl -sI https://beckon.shubham.club/latest/Beckon.dmg | head -3`
returns a 302 to the new file; `curl -s https://beckon.shubham.club/appcast.json | jq .version`
shows the new version; the GitHub release page lists the same SHA-256 as `dist/SHA256SUMS.txt`.

## 9. What users see: signed vs unsigned

Beckon is downloaded through a browser, so it carries the `com.apple.quarantine` flag and
Gatekeeper evaluates it on first launch.

**Developer ID signed + notarized + stapled (the goal)**

- macOS 14 / 15 / 26: the dmg opens, the app launches with no dialog at all. If the Mac is offline
  the stapled ticket is used, so it still launches.
- Later updates launch silently too, as long as each build is notarized.

**Signed with Developer ID but not notarized**

- macOS 15 and 26: *"Beckon" Not Opened. Apple could not verify "Beckon" is free of malware…* with
  only *Done* / *Move to Trash*. The user must go to System Settings → Privacy & Security → *Open
  Anyway*, then confirm with password/Touch ID. Most users give up here. Do not ship this.

**Ad-hoc / unsigned (what `release.sh` produces without `BECKON_SIGN_IDENTITY`)**

- macOS 14: right-click → Open offers an *Open* button in the dialog.
- macOS 15 (Sequoia) removed the right-click → Open shortcut. The only path is: try to open once →
  *Done* → System Settings → Privacy & Security → scroll to Security → **Open Anyway** → authenticate.
- macOS 26 (Tahoe): same as 15. Depending on the download path the dialog may instead say the app
  *"is damaged and can't be opened"*; that is the quarantine flag plus a broken signature, and the
  user has to run `xattr -dr com.apple.quarantine /Applications/Beckon.app` in Terminal.
- The site FAQ (`#gatekeeper`) documents these steps for anyone who ends up with such a build.

Because Beckon is a background menu-bar app (`LSUIElement`), a blocked launch is extra confusing:
nothing visible happens except the dialog. Signing and notarizing is not optional for a public release.

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `Signing identity not found in any keychain` | `security find-identity -v -p codesigning`; the string must match exactly, including `(TEAMID)`. In CI, check the `.p12` includes the private key (export *2 items*). |
| `errSecInternalComponent` during codesign | Keychain locked or key not usable by codesign: `security unlock-keychain`, or re-run `set-key-partition-list` as the workflow does. |
| notarytool: `The operation couldn't be completed. Unable to locate credentials` | Profile name wrong or stored in another keychain. Re-run `xcrun notarytool store-credentials`. |
| Notary status `Invalid`, log says *The signature does not include a secure timestamp* | Network blocked `timestamp.apple.com` during signing. Re-run signing online. |
| Notary log: *The executable does not have the hardened runtime enabled* | A nested binary was not signed with `--options runtime`; `release.sh` signs `beckon-hook` separately for this reason; check for new helper binaries. |
| `spctl` rejects a notarized app | Stapling failed or the ticket is not yet propagated; `xcrun stapler validate dist/.../Beckon.app`, wait a minute, retry. |
| Version mismatch in CI | Tag `vX.Y.Z` must equal `CFBundleShortVersionString`. |
| Users report the update checker never fires | `BeckonUpdateFeedURL` missing from `Info.plist`, or `appcast.json` is not valid JSON (`jq . site/appcast.json`). |
