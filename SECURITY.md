# Security

To report a vulnerability, use **GitHub → Security → Report a vulnerability** on this repo. Please don't open a public issue.

## Design notes

- **No accounts, no ads, no analytics.**
  - Reading history and the learned interest profile stay on the device.
  - Android backup is disabled.
  - The app never asks for location.
- **Crash reports.** These are the only thing the app sends about itself, and they are opt-out in Settings.
  - Each report contains only the error, the stack trace, the app version and the Android version.
  - Query strings, e-mail addresses and long numbers are removed from the error text on the phone.
  - The Worker never stores IP addresses. Rate limiting uses a daily-salted hash.
  - Reports expire after 30 days.
- **Updates.**
  - The app accepts the manifest and APK only over HTTPS from GitHub hosts.
  - The manifest must include the APK's SHA-256, which the app checks.
  - Android refuses any APK not signed with the original key.
- **Network (app).**
  - Traffic is HTTPS only; cleartext is disabled.
  - Requests to localhost, private, link-local or CGNAT addresses are refused, and so are redirects to them. The check also runs on the DNS result.
  - Responses are size-capped and time-limited.
- **Untrusted content.** Feeds, article pages and Wikidata are all treated as untrusted:
  - text is rendered as plain text only, with HTML and bidi/invisible control characters stripped;
  - only `http(s)` links can be opened;
  - SPARQL inputs are validated;
  - remote catalog entries are schema-checked.
- **Crawler** (GitHub Actions).
  - It fetches only public addresses: private and metadata IPs are refused, including through redirects.
  - It uses the Python standard library only, with no third-party packages.
- **Worker** (Cloudflare).
  - `/og` accepts only public http(s) URLs.
  - The admin route needs a bearer token, compared in constant time.
  - Crash writes are rate-limited per phone and capped per hour, so they can't exhaust the KV quota the feed copy needs.
  - Secrets (`ADMIN_TOKEN`, `SALT`, `GH_TOKEN`) are Worker secrets and never in the repo.
  - `GH_TOKEN` is a fine-grained token with Actions access to this repo only.
- **CI.**
  - Actions are pinned to commit SHAs, and Dependabot proposes updates.
  - The build job is read-only. Only the release job can write, and it runs no third-party code.
  - The signing key is decoded only for the build step and deleted right after.
