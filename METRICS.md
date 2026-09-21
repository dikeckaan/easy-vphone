# easy-vphone metrics

## Project statistics

Updated: **2026-09-20 13:16 UTC**. Counts are events, not installs or people.

| Metric | Count |
|---|---:|
| ZIP downloads across releases | 3 |
| Stars | 2 |
| Forks | 0 |
| Watchers | 0 |
| Open issues + pull requests | 0 |
| Clones, last 14-day snapshot | 32 |
| Unique cloners, same snapshot | 20 |
| Page views, last 14-day snapshot | 3 |
| Unique visitors, same snapshot | 3 |

[Detailed release downloads, daily clone/view history and collection timestamps](METRICS.md).
GitHub does not expose unique downloaders. Clone/view uniqueness is limited to the reported window; daily uniques must not be summed as people.
Automated builds and verification downloads can contribute to these counters.

## Release assets

| Release | Asset | Downloads | Bytes |
|---|---|---:|---:|
| v0.2.0 | easy-vphone-0.2.0-arm64.zip | 3 | 483040 |
| v0.2.0 | SHA256SUMS | 1 | 94 |

## Clones

Last successful traffic snapshot: **2026-09-20 13:16 UTC**.
14-day total: **32**; unique cloners: **20**.

Archived daily counters (UTC; newest day can be incomplete). These are events, not lifetime unique people.

| Day | Events | Unique that day |
|---|---:|---:|
| 2026-09-19 | 1 | 1 |
| 2026-09-18 | 0 | 0 |
| 2026-09-17 | 2 | 2 |
| 2026-09-16 | 29 | 17 |
| 2026-09-15 | 0 | 0 |
| 2026-09-14 | 0 | 0 |
| 2026-09-13 | 0 | 0 |
| 2026-09-12 | 0 | 0 |
| 2026-09-11 | 0 | 0 |
| 2026-09-10 | 0 | 0 |
| 2026-09-09 | 0 | 0 |
| 2026-09-08 | 0 | 0 |
| 2026-09-07 | 0 | 0 |
| 2026-09-06 | 0 | 0 |
| 2026-09-05 | 0 | 0 |
| 2026-09-04 | 0 | 0 |
| 2026-09-03 | 0 | 0 |

## Page views

Last successful traffic snapshot: **2026-09-20 13:16 UTC**.
14-day total: **3**; unique visitors: **3**.

Archived daily counters (UTC; newest day can be incomplete). These are events, not lifetime unique people.

| Day | Events | Unique that day |
|---|---:|---:|
| 2026-09-19 | 0 | 0 |
| 2026-09-18 | 1 | 1 |
| 2026-09-17 | 0 | 0 |
| 2026-09-16 | 2 | 2 |
| 2026-09-15 | 0 | 0 |
| 2026-09-14 | 0 | 0 |
| 2026-09-13 | 0 | 0 |
| 2026-09-12 | 0 | 0 |
| 2026-09-11 | 0 | 0 |
| 2026-09-10 | 0 | 0 |
| 2026-09-09 | 0 | 0 |
| 2026-09-08 | 0 | 0 |
| 2026-09-07 | 0 | 0 |
| 2026-09-06 | 0 | 0 |
| 2026-09-05 | 0 | 0 |
| 2026-09-04 | 0 | 0 |
| 2026-09-03 | 0 | 0 |

## Collection and limitations

- Public release/stars/forks counters refresh every six hours through GitHub Actions.
- Traffic requires additional repository access. If Actions cannot read it, the last successful snapshot and its timestamp remain visible.
- The owner’s local collector can refresh traffic using the existing gh login; no account token is committed or copied into repository secrets.
- GitHub exposes only the last 14 days of traffic. Daily snapshots are merged by UTC date to avoid double-counting; missed days older than that cannot be recovered.
- ZIP downloads include manual downloads, Homebrew downloads and validation downloads. They do not count installs or unique people.
- Source ZIP downloads and git clones are different metrics. There is no lifetime unique clone/download count here.
- No telemetry is collected from the app. Update checks only request public release metadata from GitHub.

[GitHub traffic API](https://docs.github.com/en/rest/metrics/traffic) · [Release asset API](https://docs.github.com/en/rest/releases/assets)
