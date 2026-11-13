# Parallax News privacy policy

Last updated: November 2026

Parallax News has no accounts, ads, analytics or tracking. The app shows the same text under Settings > Privacy policy.

## What stays on your phone

These never leave your phone:
- the places and topics you follow,
- your reading history,
- your thumbs up and down,
- the interest model the app learns from what you open.

Uninstalling the app, or tapping "Reset" in Settings, deletes them.

## Services the app contacts

To show news, the app downloads public data directly from the services below. Like any website, each one sees your IP address and what was requested (for example a search term), and handles it under its own privacy policy.

- **News:** Google News, Bing News, publishers' RSS feeds, and article pages for preview images.
- **Outlet and place data:** Wikidata.
- **The crawler feed and app updates:** GitHub, and our Cloudflare Worker.

Our crawler runs on GitHub's servers, not on your phone. It may also use official news APIs (The Guardian, The New York Times, NewsData.io, GNews, NewsAPI), and it never sends them anything about you.

## Crash reports

When the app crashes, it sends a crash report to our Cloudflare Worker. The report contains:
- the error message,
- where in the code the error happened,
- the app version and the Android version.

It never contains your reading history, places, location or anything else that identifies you. The Worker does not store IP addresses: it uses a salted hash, reset daily, to limit how many reports each phone can send. Reports are deleted after 30 days. You can turn crash reports off in Settings.

## Location

The app never asks for your location. It guesses your home country from your network's region, and you can change it in Settings.

## Children

Parallax News is a general news reader. It is not directed at children under 13.

## Changes and contact

Changes to this policy ship with app updates and appear in this file's history. For questions, [open an issue](https://github.com/JackLongman12/parallax-news/issues).
