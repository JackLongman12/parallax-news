# Security

Please report vulnerabilities privately via **GitHub → Security → Report a vulnerability** on this repo. Don't open a public issue.

## Design notes

- **No accounts, no server, no telemetry.** Reading history and the learned interest profile stay on the device, and adb backup is disabled.
- **Updates.** The app only accepts HTTPS from GitHub hosts, requires a SHA-256 in the manifest, and Android refuses any APK not signed with the original key.
- **Network.** Traffic is HTTPS-only (cleartext disabled). Requests and redirects to localhost, private, link-local or CGNAT addresses are refused, including by DNS resolution. Responses are size-capped and time-limited.
- **Untrusted content.** Feeds, Wikidata and OpenStreetMap are untrusted:
  - text is rendered as plain text only, with HTML stripped and bidi/invisible control characters removed;
  - only `http(s)` links can be opened;
  - SPARQL inputs are validated;
  - remote catalog entries are schema-checked.
- **CI.** Actions are pinned to commit SHAs. The build job is read-only. Only the release job, which runs no third-party code, can write. The signing key is deleted right after the build.
