# Launch checklist

## 1. Official API keys (free; all optional)

The crawler and the Worker turn each source on as soon as its key is set. Only you can create the accounts. Keys stay in GitHub or Cloudflare secrets and never ship in the app.

| Secret | Sign up | Free limit | Used for |
|---|---|---|---|
| `GUARDIAN_KEY` | open-platform.theguardian.com | 5,000/day | Guardian headlines (crawler) |
| `NYT_KEY` | developer.nytimes.com (Times Newswire API) | 500/day | NYT headlines (crawler) |
| `NEWSDATA_KEY` | newsdata.io | 200 credits/day | Multi-language news (crawler, every 30 min) |
| `GNEWS_KEY` | gnews.io | 100/day | Top headlines (crawler, every 20 min) |
| `NEWSAPI_KEY` | newsapi.org | 100/day | Top headlines (crawler, every 20 min) |
| `FINNHUB_KEY` | finnhub.io | 60/min | Official stock prices (crawler) and backup symbol search (Worker) |

Add the crawler keys to GitHub, one command per key:

```
gh secret set GUARDIAN_KEY
```

Add Finnhub to the Worker as well:

```
cd worker && npx wrangler secret put FINNHUB_KEY && npx wrangler deploy
```

While you're in the Worker, set `GH_TOKEN` (a fine-grained token with Actions read/write on this repo only). It lets the Worker restart the crawler if GitHub's schedule stalls.

Check a crawl log for `news APIs: {...}` and `official prices from Finnhub` to confirm the keys work.

## 2. Before anyone else installs it

- [ ] Test on a real phone: every tab, updating, offline mode, the largest font size and a small screen.
- [ ] Back up `secrets/signing.keystore` somewhere other than this PC. If it's lost, installed apps can never update again.
- [ ] Review the outlet ratings in `assets/sources.json`. They follow the method in Settings > How we rate outlets.
- [ ] Make sure no other app or company already uses the name "Parallax News".

## 3. GitHub releases (works now)

Every push to `main` publishes `vX.Y.N` with the APK, which updates itself, and a Play bundle (`-play.aab`).

## 4. Google Play

1. Create a Play Console developer account ($25, one-time).
2. Create the app with package `com.parallaxnews.parallax_news`.
3. Upload the `-play.aab` from the latest release. Play App Signing uses your keystore as the upload key. The Play build has no built-in updater and doesn't request permission to install apps.
4. Store listing: copy the text and images from `fastlane/metadata/android/en-US/`. Privacy policy URL: `https://github.com/JackLongman12/parallax-news/blob/main/PRIVACY.md`.
5. Data safety form:
   - No data collected or shared.
   - Approximate location is used on the device only, and the user must turn it on.
   - Data is encrypted in transit (HTTPS only).
6. Content rating: News. Target audience: 13+.
7. New personal accounts must run a closed test with 12 testers for 14 days before going to production.

## 5. F-Droid

F-Droid builds the app from source and reads `fastlane/metadata`. Submit a merge request to `fdroiddata` with a recipe that:
- runs `flutter create` and `tool/prepare_android.py` with `CHANNEL=fdroid`, which drops the self-updater permission;
- builds with `--dart-define=CHANNEL=fdroid`.

Expect the "NonFreeNet" label, because the app uses Google News and Yahoo.
