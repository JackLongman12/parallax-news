# Launch and operations

The app is distributed as a signed APK on GitHub Releases. It updates itself.

## How the backend stays up

| Part | Runs on | If it fails |
|---|---|---|
| Crawler (`crawler/crawl.py`) | GitHub Actions, every 5 min. Each run starts the next one. | The Worker keeps serving the last good feed. Its cron restarts the crawler after 12 min without a new feed (needs `GH_TOKEN`). |
| Feed file | The `feed` release on GitHub | The Worker serves its own copy in Cloudflare KV, refreshed every 5 min. |
| Worker (`worker/`) | Cloudflare, free plan | The app downloads the feed from GitHub directly. |
| Both down | | The app shows the last feed saved on the phone, then falls back to fetching Google and Bing itself. |
| Updates | GitHub release `latest.json`, then the GitHub API | Updates wait. The app keeps working. |

Each layer covers the one before it. A user sees no news only if GitHub, Cloudflare and Google News are all unreachable on a phone that has never loaded the feed.

**Uptime alerts:** `.github/workflows/uptime.yml` checks `/health` and `/feed` every 30 minutes from GitHub's network. If either fails, it opens an issue titled "Uptime: news feed is down or stale", and GitHub e-mails you. It closes the issue when the feed recovers.

## Crash reports

The app posts crashes to the Worker at `/crash`. They are grouped by error and kept for 30 days. To read them:

```
python tool/crashes.py
```

That lists every crash group. To show the full stack trace of one group:

```
python tool/crashes.py <id>
```

The admin token is in `secrets/worker_admin_token.txt`, which git ignores. Release builds are obfuscated. To turn a stack trace back into readable code, download `symbols-1.0.N.zip` from the matching release, then run:

```
flutter symbolize -i trace.txt -d app.android-arm64.symbols
```

## Crawler watchdog

The Worker's `GH_TOKEN` secret (set) lets its cron restart a stalled crawler. It is a fine-grained token with Actions read/write on this repo only, valid for one year. To replace it when it expires, create a new one the same way, then from the `worker` folder in PowerShell run:

```
npx.cmd wrangler secret put GH_TOKEN
```

## Before telling people about it

- [ ] Test on a real phone: every tab, an update, offline mode, the largest font size, a small screen.
- [ ] Back up `secrets/` somewhere other than this PC. It holds the signing keystore and the Worker admin token. If you lose the keystore, installed apps can never update again.
- [ ] Review the outlet ratings in `assets/sources.json`, following the method in Settings > How we rate outlets.
- [ ] Check that no one else already uses the name "Parallax News".
