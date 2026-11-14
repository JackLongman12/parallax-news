# Parallax News

![Parallax News](docs/img/feature_graphic.png)

**Every side of every story, from the world to your street.** Open-source, bias-aware news for Android. No account, no ads, no tracking, free.

<p>
  <img src="docs/img/01_for_you.png" width="19%" alt="Feed">
  <img src="docs/img/03_story_coverage.png" width="19%" alt="Story coverage">
  <img src="docs/img/04_blindspot.png" width="19%" alt="Blindspots">
  <img src="docs/img/05_explore.png" width="19%" alt="Explore">
  <img src="docs/img/06_sources.png" width="19%" alt="Sources">
</p>

**[Download the latest APK](https://github.com/JackLongman12/parallax-news/releases/latest)**. Allow "Install unknown apps" once; after that the app updates itself.

## Features

- **Left / center / right coverage** for every story, with each outlet's lean, factuality, ownership and state affiliation.
- **Blindspots:** stories one side of the spectrum barely covers.
- **World to your street:** continents, countries, states, cities and neighbourhoods. Local papers, radio and TV for any place are found through Wikidata.
- **25 topics**, from politics and world news to AI, space, gaming and weather, drawn from about 390 rated outlets.
- **A daily feed curated on your phone:** it learns what you read without sending anything anywhere.
- **Home-screen widget** with the daily briefing.
- **Self-updating:** checks GitHub Releases at startup and verifies the SHA-256 before installing.

## How it works

- **Crawler** (`crawler/`, GitHub Actions): gathers headlines from Google News, Bing News and outlet RSS feeds, groups them into stories, and publishes the feed.
- **Worker** (`worker/`, Cloudflare): serves a cached copy of the feed and wakes the crawler if the feed goes stale. It also accepts anonymous crash reports.
- **App** (`lib/`, Flutter): loads the feed from the Worker. If that fails it falls back to GitHub, and then to the last copy saved on the phone, so it keeps working offline.

All of it runs on free tiers.

## Privacy

Nothing you follow, read or rate leaves your phone. Crash reports carry no personal data: the app strips URLs, emails and long numbers first. You can turn them off in Settings. Details are in [PRIVACY.md](PRIVACY.md), and security reports go through [SECURITY.md](SECURITY.md).

## Build

CI (`.github/workflows/android.yml`) generates the Android project, runs analysis and tests, renders the screenshots above, and builds a signed APK on every push to `main`. Each push publishes a GitHub Release with the APK and `latest.json`.

One-time setup:
1. Run `python tool/make_keystore.py` and back up `secrets/` (`python tool/backup_secrets.py` writes an encrypted copy).
2. Run `gh secret set ANDROID_KEYSTORE_B64 < secrets/signing.keystore.b64`.

Launch steps are in [docs/LAUNCH.md](docs/LAUNCH.md). The launch films are rendered from code in [tool/launch-video](tool/launch-video).

## Contributing ratings

Edit `assets/sources.json`. Bias codes are `FL L LL C LR R FR`, relative to the outlet's country. Local outlets can be added on Wikidata, and the app picks them up automatically.

Data comes from Google News and Bing News RSS, outlet feeds, and Wikidata (CC0). The app shows headlines and links only. MIT licensed.
