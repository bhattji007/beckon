# beckon.shubham.club

Static landing page for Beckon. No build step, no framework: `index.html`, `style.css`, `appcast.json`,
`_redirects`, `_headers`, the media (`demo.mp4`, `demo-poster.jpg`, `og.png`, `assets/`), plus the binaries
under `releases/`.

`assets/shots/*.webp` are real overlay snapshots taken from the running app (`BECKON_SNAPSHOT_DIR=/dir open
--env BECKON_SNAPSHOT_DIR=/dir /Applications/Beckon.app`, then fake hooks through `~/.beckon/bin/beckon-hook`;
see `CONTRIBUTING.md`). Retake them after an overlay redesign. `assets/fonts/` holds the two self-hosted
typefaces (Familjen Grotesk, JetBrains Mono; OFL, the same two the app bundles). `demo.mp4` is currently a transcode of
`videos/01-toast-stack.mp4` (the first design); drop the real screen recording over it (and a new `demo-poster.jpg`).

## Layout as served

| Path | What | Where it comes from |
|---|---|---|
| `/` | landing page | `index.html`, `style.css` |
| `/demo.mp4`, `/demo-poster.jpg` | demo video + poster | screen recording (today: transcode of `videos/01-toast-stack.mp4`) |
| `/og.png` | social preview card | rendered once with Playwright; regenerate if the headline changes |
| `/assets/shots/*.webp` | real overlay snapshots used on the page | `BECKON_SNAPSHOT_DIR` + fake hooks, converted with `cwebp` |
| `/appcast.json` | update feed read by the app (`BeckonUpdateFeedURL`) | `dist/appcast.json` from `release/release.sh` |
| `/releases/Beckon-<version>.dmg` / `.zip` | the downloads | `dist/Beckon-<version>.*` |
| `/latest/Beckon.dmg`, `/latest/Beckon.zip` | stable links the Download button uses (302 to the newest version) | `_redirects`, regenerated as `dist/_redirects` |

The appcast schema is one object: `{"version","url","notes","published"}`. The app compares `version`
(semver) with its own `CFBundleShortVersionString` and offers `url` as a download link; nothing is
installed automatically. Keep the file small and keep `url` pointing at a dmg under `/releases/` so
old links never break.

## Publishing a release

After `release/release.sh` has produced `dist/`:

```sh
mkdir -p site/releases
cp dist/Beckon-*.dmg dist/Beckon-*.zip site/releases/
cp dist/appcast.json dist/_redirects site/
git add site && git commit -m "site: release $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' app/Info.plist)"
git push
```

Then deploy (see below). Check `https://beckon.shubham.club/appcast.json` shows the new version and
that `https://beckon.shubham.club/latest/Beckon.dmg` downloads the new dmg.


## Hosting: Cloudflare Worker with static assets

Live at https://beckon.shubham.club, served the same way as jageshwar.shubham.club: a Cloudflare Worker whose
only job is to serve this directory as static assets. `wrangler.jsonc` names the worker (`beckon-site`) and the
custom domain; wrangler creates the DNS record and certificate on first deploy. `.assetsignore` keeps the config
and these notes out of the upload. `_redirects` and `_headers` are honoured by the assets runtime.

```sh
cd site
npx wrangler deploy
```

Preview locally with the same redirects and headers: `npx wrangler dev` from `site/`.

Limits that matter: 25 MB per file. Beckon's dmg is ~2 MB, so `releases/` can hold many versions. If the dmg
ever grows past 25 MB, host `releases/` on R2 (or the GitHub release assets) and change `BECKON_DOWNLOAD_BASE`
+ `_redirects` to point there.

A Cloudflare Pages project (`beckon`, https://beckon-6bk.pages.dev) also exists from the first deploy and can be
refreshed with `npx wrangler@3 pages deploy site --project-name beckon`; the custom domain lives on the Worker.
Any other static host (GitHub Pages, Netlify, S3 + CloudFront, nginx) works too; only the `/latest/*` redirects
need an equivalent (or point the button at the versioned file directly).
