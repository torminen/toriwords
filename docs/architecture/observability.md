# Observability: crash reports and usage statistics

Status: **Confirmed** (owner, 2026-11-10): **no analytics and no crash-reporting SDK in v1** ([decision](memory://44)). §2 below is a proposal kept for later. It is not in v1 and needs an owner decision.

Related:
- Decisions: [no analytics in the MVP](memory://44), [local-first with own backend](memory://8), [open source, no secrets in clients](memory://12), [v1 scope](memory://15).
- Architecture: [backend.md](backend.md), [auth.md](auth.md) §9 (privacy label).

## 1. v1 position

**What v1 does not have:**
- The apps send **no usage data and no crash reports** of their own.
- No analytics SDK, no crash SDK (no Sentry, no Crashlytics).
- No telemetry endpoint on the backend.
- No DSN or ingest key in the repository or in release CI.
- No local telemetry tables.

**Where crash and performance visibility comes from:** only what the platforms provide without app code.

| Platform | Source | Coverage |
|---|---|---|
| iOS | App Store Connect / Xcode Organizer: crash reports, hangs, energy and launch metrics (MetricKit-based aggregates) | Only users who allowed "Share with App Developers" in iOS settings; delayed by about a day. TestFlight builds report crashes and feedback too. |
| Android | Google Play Console → Android vitals: crash and ANR rates, stack traces (deobfuscated with the R8 mapping uploaded at release) | Only users who allowed usage & diagnostics on the device; delayed. |

**Release process requirements** (no app code involved):
- Archive the dSYMs with each iOS build (Xcode does this by default).
- Upload the R8 `mapping.txt` with each Play release. Otherwise Play stack traces stay obfuscated.

**Consequences:**
- Settings has no privacy or analytics switches; no consent prompt is needed.
- Store labels:
  - App Store: only "Data linked to you: user content, identifiers", for app functionality and only for signed-in users ([auth.md](auth.md) §9).
  - Play Data safety: the same.
- Product questions like retention, capture-method use or dictionary hit rate cannot be measured in v1. Owner feedback and store reviews are the only sources.

## 2. Later (not in v1, needs owner decision)

This was the architect's proposal for v1. The owner deferred it ([memory://44](memory://44)). It is kept so it can be picked up without redoing the analysis. If revived, it would add:
- `POST /v1/telemetry/daily` to [backend.md](backend.md);
- Settings switches, which are product scope;
- a local `telemetry_reports` table, which is [local-storage.md](local-storage.md) scope.

### L1. Constraints

| # | Constraint | Consequence |
|---|---|---|
| C1 | Open-source clients, no secrets ([memory://12](memory://12)). | Only public ingest keys may be embedded (e.g. a Sentry DSN). This is acceptable only if the worst abuse is bounded: quota exhaustion or junk data, never cost overruns or data access. |
| C2 | Local-first ([memory://8](memory://8)). | Reports are queued on the device and sent opportunistically. They never block start-up, capture, review or sync. If the queue fails, data is dropped silently. |
| C3 | No account needed. | Reports carry no account ID, Device ID or provider subject, even when the user is signed in. |
| C4 | **No install ID** (this proposal). | Nothing ties two reports from one device together. Retention is measured with counters computed on the device (§L4.2) instead. |
| C5 | **The user's vocabulary never leaves the device through telemetry.** | No words, translations, contexts, source titles or URLs. No screenshots, view hierarchies or session replay. Breadcrumbs hold only screen names. |
| C6 | User control. | Settings → Privacy has two switches: "Send crash reports" and "Send anonymous usage statistics". Turning a switch off deletes its queue immediately. |
| C7 | Parity. | Both apps send the same statistics report (§L4), checked by fixtures. Crash reporting is platform-native by nature; only its configuration must match. |
| C8 | Hosting abroad (EU, [backend.md](backend.md) §L4.1). | GDPR applies (§L6). |
| C9 | Forks and dev builds. | The DSN and the statistics endpoint are injected only by the official release CI. Debug builds and forks have them empty, so both switches are hidden and nothing is sent. |

### L2. Crash reporting: options

| | (a) MetricKit + Play vitals only | (b) Sentry SaaS (EU region) | (c) Sentry-compatible self-hosted | (d) Firebase Crashlytics | (e) Own endpoint on our backend |
|---|---|---|---|---|---|
| What we get | iOS: Xcode Organizer crash and hang reports; MetricKit payloads on device. Android: Play Console vitals (crash rate, ANRs, stack traces). | Symbolicated crash and error reports, grouping, alerts, release tagging; both platforms in one tool. | Same SDKs, on our own server. | Symbolicated crashes, grouping, alerts. | Whatever we build. |
| Coverage | Only users who allowed sharing diagnostics with developers at OS level (iOS opt-in, Android usage & diagnostics). Partial and delayed (~1 day). | Every user with the switch on. | Same as (b). | Same as (b). | Same as (b). |
| Client code | None (MetricKit optional). | SDK (`sentry-cocoa`, `sentry-android`, MIT). | Same as (b). | Firebase SDK + `GoogleService-Info.plist` / `google-services.json` in the public repo. | Native crash capture is hard to write correctly. Use MetricKit on iOS and `ApplicationExitInfo` + an uncaught-exception handler on Android. |
| Symbolication | Done by Apple and Google. | Upload dSYMs and R8 mappings from CI; the auth token lives in CI secrets only. | Sentry self-hosted: full support. GlitchTip (light, open source): native symbolication is limited (`not verified`). | Automatic. | We would build dSYM (`atos`) and R8 retrace pipelines ourselves. |
| Identifiers | None. | Auto session tracking adds a random installation ID; **we turn it off** (§L5). | Same as (b). | Firebase Installation ID, always present. Conflicts with C3/C4. | None. |
| Third party sees | Apple, Google (already the platform). | Sentry (US company, data stored in Frankfurt): stack traces, device model, OS, IP (not stored when configured). | Nobody. | Google. | Nobody. |
| Cost | Free. | Free developer tier (≈5k errors/month, `not verified` for Nov 2026). Paid on-demand budget set to 0, so abuse can only exhaust the quota. | Sentry self-hosted needs ~16 GB RAM and ~20 containers: far above our VPS. GlitchTip fits a 2–4 GB VPS. | Free. | Days of work, then ongoing maintenance. |
| Abuse of the public key (C1) | n/a | DSN is public by design; rate limits, spike protection and a zero overage budget bound it. | Our own rate limits. | API key is public by design; bounded by Firebase. | Our own rate limits. |

### L3. Usage statistics: options

| | (a) Self-hosted PostHog / Plausible-like | (b) TelemetryDeck (SaaS) | (c) Own minimal endpoint on our backend |
|---|---|---|---|
| Model | Event stream with a distinct ID (PostHog); page-view model (Plausible, web-first). | Signals with a hashed per-install user ID by default. Swift SDK first-class, Kotlin SDK available. | **One aggregated report per device per day**, with no ID (§L4). |
| Hosting | PostHog self-hosted needs ClickHouse, Kafka and Redis: 8 GB+ RAM. Plausible needs ClickHouse, ~2 GB. Both are larger than the app backend itself. | EU company and hosting. Free tier ≈100k signals/month (`not verified` for Nov 2026). | Same Ktor service and Postgres; one table. |
| Identifiers | Distinct ID per install (can be randomised per session). | Hashed install ID (salted). | None. |
| Analysis | Funnels, paths, dashboards. | Dashboards and funnels. | SQL views; a simple dashboard (e.g. Metabase or Grafana) later if wanted. |
| Parity | Two SDKs, same event names by convention. | Two SDKs, same signal names by convention. | One JSON schema plus fixtures (§L4.3). |
| Third party sees | Nobody. | TelemetryDeck. | Nobody. |
| Fits "no identifiers" (C3, C4) | Only with effort. | Partly (pseudonymous ID). | Yes. |

### L4. Proposed design (deferred)

**Crash reports: (b) Sentry SaaS, EU region**, configured as in §5, plus (a) MetricKit / Play vitals as a free, always-on baseline. Symbolicated, grouped crashes from both platforms are the main value, and building that ourselves (e) costs more than the rest of observability together. Crashlytics is rejected because of the Firebase Installation ID and a Google SDK in a privacy-first open-source app. Exit path: if the owner prefers no third party, GlitchTip self-hosted with the same SDKs, after checking its iOS and Android symbolication (`not verified`).

**Usage statistics: (c) own minimal endpoint**, `POST /v1/telemetry/daily`.
- It needs no third party, no identifiers and no extra infrastructure.
- It has one schema for both apps, so parity is testable.
- The questions v1 needs (§L4.1) are answerable from daily aggregates. Funnels and per-user paths are deliberately out of scope.

#### L4.1 Questions the statistics answer

| # | Question | Fields (§L4.2) |
|---|---|---|
| Q1 | Do people keep using the app after 1, 4, 12 weeks? | `cohortWeek`, `activeDays7`, `activeDays28` |
| Q2 | How do words get in: share/selection capture, manual add, import? | `added.*` |
| Q3 | Is the bundled dictionary enough, or do we fall back to MT too often? | `enrich.*` |
| Q4 | Do people review, and is the scheduler sane (again rate, backlog)? | `reviews.*`, `dueBucket` |
| Q5 | How large do vocabularies get? | `entriesBucket` |
| Q6 | Are account/sync, widget and reminders used? Does sync fail? | `signedIn`, `widget`, `reminders`, `syncErrors` |
| Q7 | Which OS and app versions are in use (to plan minimum OS)? | `platform`, `osMajor`, `appVersion` |
| Q8 | How often does the app crash (crash-free days)? | `crashedRuns` |

#### L4.2 The daily report

The app counts locally during the review day (the same 04:00 boundary as the scheduler, [scheduler.md](scheduler.md) §4). When a day is over, at the next launch, it builds one report for that day.

```json
{
  "schema": 1,
  "day": "2026-11-09",
  "platform": "ios",
  "osMajor": 27,
  "appVersion": "1.0.3",
  "uiLanguage": "ru",
  "cohortWeek": "2026-W44",
  "activeDays7": 5,
  "activeDays28": 12,
  "signedIn": true,
  "widget": true,
  "reminders": false,
  "entriesBucket": "200-999",
  "dueBucket": "1-19",
  "added": { "capture": 3, "manual": 1, "import": 0 },
  "enrich": { "dictionary": 3, "mt": 1, "none": 0 },
  "reviews": { "again": 4, "hard": 2, "good": 25, "easy": 3, "sessions": 2 },
  "tts": 6,
  "syncErrors": 0,
  "crashedRuns": 0
}
```

Rules:
- A report exists only for days with the app opened (an active day). So reports per `day` = daily active devices.
- `cohortWeek` is the ISO week of the first launch. It is the only stable attribute, and it is shared by every device that installed that week.
- Buckets: entries `0`, `1-49`, `50-199`, `200-999`, `1000+`; due `0`, `1-19`, `20-99`, `100+`. Exact sizes could make a device recognisable across days.
- Counts are capped at 1000 per field.
- `uiLanguage` is `ru`, `en` or `other`. No region, time zone or device model.
- Unknown fields are ignored by the server; a new field means `schema` + 1.

**Queue and sending (C2):**
- Reports are stored in a local, never-synced table: at most the last 7 reports; older ones are dropped.
- Sending: one batched request (`{"reports": […]}`) on app launch or foreground, at most once per hour, in the background, with a 10 s timeout. Failure means retry next time; nothing is shown to the user.
- The endpoint needs no auth and sends no `Authorization` header, even when the user is signed in, so a report cannot be joined with an account.

**Server:**
- It validates the schema and stores rows `(received_date, report jsonb)`. There is no IP, no user agent and no exact receive time.
- Caddy does not log this path.
- Abuse is bounded by a 10-requests-per-minute limit per IP (counted in memory, never stored), a 7-report batch maximum and a 16 KB body limit. The worst case is skewed statistics, which can be filtered out.
- Rows are kept 25 months, then deleted.

#### L4.3 Parity

`spec/fixtures/telemetry/` holds:
- the JSON schema;
- cases of the form "activity log of a day → expected report", covering the 04:00 boundary, bucket edges, capping, and active-day counters across a gap.

Both apps compute the report from the same domain events, so it is tested like the rest of the domain core ([parity-testing.md](parity-testing.md)).

### L5. Sentry configuration (both platforms)

| Setting | Value | Why |
|---|---|---|
| Region | EU (`*.de.sentry.io`) | Data stays in the EU (C8). |
| `sendDefaultPii` | false; server option "Prevent storing of IP addresses" on | C3 |
| User / installation ID | none; auto session tracking **off** (it creates a random installation ID) | C4. Crash-free rate comes from `crashedRuns` (§L4.2) instead. |
| Attachments, screenshots, view hierarchy, session replay | off | C5 |
| Breadcrumbs | navigation (screen names) and sync state only; no UI text, no network URLs with query strings | C5 |
| `beforeSend` | strips exception messages that could contain user text (e.g. SQLite errors with values); keeps the type and stack | C5 |
| Performance tracing | off in v1 | Quota, privacy |
| Offline | the SDKs' on-disk envelope cache (built in) | C2 |
| Environment / release | `release` = version + build; `dist` = platform | Grouping |

Both apps share this table; a CI check compares the two configuration files against it.

### L6. Consent default and privacy labels

**Default: on (opt-out) or off (opt-in)?** This is option L-O1 (§L7).

| | Opt-out (on by default, disclosed on first run and in Settings) | Opt-in (off until the user turns it on) |
|---|---|---|
| Data volume | Most users. | Typically a small minority opts in. Statistics are biased towards engaged users. |
| GDPR / ePrivacy (EU hosting, EU users) | Statistics (§L4.2) have no identifier and coarse buckets, which arguably makes them non-personal data. Crash reports pass through Sentry with an IP address (not stored) and device details, so they rely on legitimate interest plus an easy opt-out. Storing counters on the device for statistics may need consent under ePrivacy art. 5(3) in some readings. **`not verified`: this is not legal advice.** | Clearly compliant. |
| Store review | Both stores accept opt-out for diagnostics not linked to the user. | Same. |

**Recommendation:** split the two switches:
- **crash reports: on by default** (opt-out), with a one-line notice on the first run;
- **usage statistics: on by default** (opt-out), for the same reason;
- if the owner wants zero legal ambiguity, make **statistics opt-in** and keep crash reports opt-out.

**App Store privacy label** (adds to [auth.md](auth.md) §9):
- Data *not* linked to you: Diagnostics (Crash Data, Performance Data, Other Diagnostic Data) and Usage Data (Product Interaction).
- Not used for tracking, so no App Tracking Transparency prompt.

**Play Data safety:**
- Collected: "App info and performance" (crash logs, diagnostics) and "App activity" (app interactions).
- Not shared: Sentry acts as a service provider.
- Encrypted in transit.
- Optional: users can turn it off.
- Deletion requests: not applicable, because the data has no identifier. The privacy policy says this.

**Privacy policy** (needed anyway for sign-in): lists Sentry as processor and the statistics fields above.

### L7. Options the owner would choose between

| # | Question | Recommendation | Alternatives |
|---|---|---|---|
| L-O1 | Default for crash reports and statistics | Both on by default (opt-out), two switches in Settings, notice on first run | Statistics opt-in, crashes opt-out; both opt-in |
| L-O2 | Crash reports via a third party | Sentry SaaS, EU region, free tier, no IDs, no user content | Self-hosted GlitchTip (needs a larger VPS, symbolication `not verified`); MetricKit + Play vitals only (no third party, partial coverage) |
| L-O3 | Statistics granularity | One anonymous daily aggregate per device, no install ID: no funnels or per-user paths | TelemetryDeck (hashed install ID, funnels; third party) |

### L8. Further extensions

- Performance metrics (launch time, hangs) from MetricKit / `ApplicationExitInfo` added to the daily report (if it exists).
- A dashboard on top of the statistics table.
- Feedback with an attached diagnostic bundle, sent only on explicit user action.
