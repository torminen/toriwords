# Backend: stack, data, hosting and API

Status: **Proposed**. Every choice below waits for owner confirmation (plan step 5).

Related:
- Decisions: [local-first with own backend](memory://8) (no BaaS), [open source](memory://12) (whether the backend is open source is **not decided**, so this document does not assume it), [project goals](memory://10), [primary pair RU → EN](memory://11).
- Architecture: [sync.md](sync.md) (the contract this backend implements), [auth.md](auth.md), [dictionary-data.md](dictionary-data.md) (data files the backend may distribute), [parity-testing.md](parity-testing.md).

## 1. Responsibilities

The backend is deliberately small:
1. **Sync store.** It stores the user's records and merges them generically: per-field LWW, tombstones and redirects ([sync.md](sync.md) §3, §6, §7, §9.3). It never reads field values.
2. **Accounts.** Sign in with Apple and Google, sessions, account deletion ([auth.md](auth.md)).
3. **Static distribution** (optional). Dictionary data packs and their manifest, if [dictionary-data.md](dictionary-data.md) chooses download over bundling.

**Not the backend's job:**
- Vocabulary rules: normalisation, duplicate detection, scheduling. These run on the clients only ([sync.md](sync.md) §1).
- Translation or LLM proxying. Enrichment is on-device or from bundled data; no paid APIs (owner input).
- Push notifications: reminders are local ([capture-and-extensions.md](capture-and-extensions.md)).
- Analytics or tracking.

Without an account, the app never contacts the backend, except for an optional anonymous download of dictionary data.

## 2. Decision B1: language and framework

| | Kotlin + Ktor 3 (JVM) | Swift + Hummingbird 2 / Vapor 4 | Go (stdlib `net/http` + pgx) | TypeScript (Node/Bun + Hono) |
|---|---|---|---|---|
| Fit with the team | Same language as the Android app; the owner maintains two languages, not three. | Same language as the iOS app. | Third language. | Third language. |
| Maturity for this job (HTTP JSON, Postgres, JWT/JWKS, OIDC) | Mature. Ktor 3.6 (Sep 2026) ships typed authentication with OpenID Connect support. Nimbus JOSE+JWT for Apple/Google token checks. Flyway for migrations. | Usable, smaller ecosystem. Fewer maintained JWT/OIDC and DB-migration libraries; Linux deployment needs more care. | Very mature, minimal dependencies. | Very mature, large ecosystem. |
| Footprint / cost | JVM: ~150–300 MB RAM; fine on a 1–2 GB VPS. | Small native binary. | Small native binary, ~20 MB RAM. | ~80–150 MB RAM. |
| Showcase value (goal G1) | Modern Kotlin server; coroutines. | High ("Swift everywhere"), but riskier. | Neutral. | Neutral. |
| Risk of code sharing with Android | Tempting to share model classes with the Android app, which [memory://7](memory://7) rules out in spirit. Mitigated: the backend does not need domain models, only the envelope. | Same, with iOS. | None. | None. |

**Recommendation: Kotlin + Ktor 3** on the current LTS JVM, with PostgreSQL via JDBC (plain SQL or jOOQ), Flyway migrations and Nimbus JOSE+JWT. It is the most mature option in a language the project already uses, and the backend is small enough that the JVM footprint does not matter. Go is the fallback if hosting must fit into a very small VPS. **No source sharing** with the Android app: the backend only knows the record envelope, so there is nothing worth sharing.

## 3. Decision B2: database

| | PostgreSQL | SQLite + Litestream (replication to object storage) |
|---|---|---|
| Fit | `jsonb` for field maps; row locks for per-user sequence counters; mature backups and tooling. | One file, no server process, cheapest. Single writer is fine for one user, but becomes a ceiling if the app ever has more users. |
| Ops | One more container, or a managed service. | Simplest; restore is a file copy. |
| Managed options | Many (Neon, provider-managed). | Few. |

**Recommendation: PostgreSQL** (current stable major). The cost difference is small, and it removes the scaling ceiling at no design cost.

### 3.1 Schema (logical)

```sql
users      (id uuid pk, seq bigint not null default 0, created_at, deleted_at null)
identities (provider text, subject text, user_id uuid fk, email text null,
            apple_refresh_token_enc bytea null, created_at,
            primary key (provider, subject))
sessions   (id uuid pk, user_id uuid fk, device_id uuid, refresh_hash bytea unique,
            family_id uuid, expires_at, revoked_at null, revoked_reason text null)
records    (user_id uuid, id uuid, type text, schema int, owner uuid null,
            deleted bool, merged_into uuid null, fields jsonb, seq bigint,
            updated_at timestamptz,
            primary key (user_id, id))
create index on records (user_id, seq);
create index on records (user_id, owner) where owner is not null;
```

- `fields` holds `{name: {v, c, u}}` exactly as in [sync.md](sync.md) §2.1. The server reads only `c` and `u`.
- `sessions.revoked_reason` keeps `account_deleted` for 90 days after a deletion, so other devices get 410 instead of a generic 401 ([auth.md](auth.md) §6). It holds no personal data.

## 4. Decision B3: hosting

| | Single VPS + Docker Compose (Caddy for TLS, Ktor, Postgres) | PaaS (Fly.io / Railway / Render) + managed Postgres (e.g. Neon) | Hyperscaler serverless (Cloud Run + Cloud SQL, or AWS equivalents) |
|---|---|---|---|
| Monthly cost at our scale | ~€5–10 | €0–25 | ~€15–40 (the managed SQL instance dominates) |
| Ops effort | OS updates, backups, monitoring are ours. | Low. | Low; more configuration. |
| Portability | Full: the same Compose file runs on any VPS, including a provider in another jurisdiction. | Medium. | Low. |
| Reachability from Russia (see §4.1) | Choose the provider and location freely. | Depends on the provider's IP ranges. | Hyperscaler ranges have been blocked or throttled in the past. |

**Recommendation: one small VPS with Docker Compose.**
- Nightly `pg_dump` plus continuous WAL archiving to object storage, with a monthly restore test.
- Uptime check; logs without personal data.
- Everything is packaged so it can move between providers in an hour, which matters because of §4.1.
- No CDN or proxy in front of the API (see §4.1).

### 4.1 Owner question: where must sync work?

Since mid-2025, Russian ISPs have throttled or cut connections to sites behind Cloudflare (the "16 KB" cut-off). Cloudflare reported similar disruption for some large Western hosts, including Hetzner, DigitalOcean and OVH. Sources: [Cloudflare blog](https://blog.cloudflare.com/russian-internet-users-are-unable-to-access-the-open-internet), [The Record](https://therecord.media/cloudflare-russia-restricting-access-crackdown), [Meduza/Zona: 16 KB curtain](https://en.zona.media/article/2025/06/19/cloudflare). The 2026 situation is changing and `not verified` for specific providers.

If the owner (or users) sync from inside Russia, the hosting location decides whether sync works at all. Options:
- (a) Host in Russia (Russian VPS providers). Sign in with Apple and Google still need the backend to reach Apple and Google servers.
- (b) Host abroad, avoid Cloudflare, and test reachability from the owner's networks.
- (c) Host abroad and rely on the user's VPN.

The app keeps working offline in every case; only backup and sync are affected. **The owner should say where they will use sync.** The recommended VPS setup supports all three options.

## 5. API

Base: `https://<api-host>/v1`. JSON, gzip/brotli. Every request carries `Toriwords-Client: ios/1.4.0` (or `android/…`) and `Toriwords-Protocol: 1`. Authenticated endpoints use `Authorization: Bearer <access token>`.

| Method + path | Purpose | Notes |
|---|---|---|
| `POST /auth/apple` | Exchange a native Apple credential (iOS): `identityToken`, `authorizationCode`, `nonce`, `deviceId` → session. | [auth.md](auth.md) §3 |
| `GET /auth/apple/start` · `POST /auth/apple/callback` | Apple web flow for Android (Services ID, `form_post`). Ends in an App Link to the app with a one-time code. | [auth.md](auth.md) §3.2 |
| `POST /auth/exchange` | Android: one-time code + PKCE verifier → session. | |
| `POST /auth/google` | Exchange a Google ID token (both platforms) → session. | [auth.md](auth.md) §4 |
| `POST /auth/refresh` | Rotate the refresh token, issue a new access token. | Reuse detection |
| `POST /auth/logout` | Revoke this device's session. | |
| `DELETE /account` | Delete the account and all its data; revoke Apple tokens. | [auth.md](auth.md) §6 |
| `GET /account` | Linked identities, device sessions, record count, storage used. | For the account screen |
| `POST /sync/push` | `{deviceId, records: [envelope…]}` → `{acked: [id…]}` | [sync.md](sync.md) §9; ≤ 500 records / 2 MB |
| `GET /sync/pull?since=<cursor>&limit=<n>[&types=a,b]` | → `{records: […], cursor, hasMore}` | `types` is used for the download-only backfill ([sync.md](sync.md) §10) |
| `GET /data/manifest.json` | Dictionary data versions, sizes, SHA-256 hashes, URLs. | Only if download is chosen. No auth. |

**Errors.** Body: `{ "error": "<code>", "message": "…" }`.

| Status | Codes | Client reaction |
|---|---|---|
| 400 | `invalid_record`, `clock_skew`, `too_large` | Log; for `clock_skew`, show a notice; skip the bad record. Sync continues. |
| 401 | `token_expired` | Refresh, then retry. |
| 401 | `session_revoked` | Local-only mode, data kept; offer to sign in again. |
| 410 | `account_deleted` | [auth.md](auth.md) §6. |
| 426 | `upgrade_required` | Work offline; ask the user to update the app. |
| 429 | `rate_limited` | Back off (`Retry-After`). |

**Limits** (generous for one person, to stop abuse of a public endpoint):
- 1M records per user;
- 60 push requests per minute per user;
- 10 sign-in attempts per minute per IP.

## 6. Dictionary data distribution

This applies only if [dictionary-data.md](dictionary-data.md) chooses download (or bundle plus updates).

| | Static files on the backend host (`/data/…` served by Caddy) | GitHub Releases of the open-source repo | Object storage + CDN |
|---|---|---|---|
| Cost | Included in the VPS (bandwidth permitting). | Free. | Small. |
| Reachability (§4.1) | Same as the API, one host to test. | GitHub is generally reachable, but `not verified` for all networks. | CDNs are the main target of throttling. |
| Licence (CC BY-SA attribution) | Attribution file served next to the data. | Release notes + attribution file. | Same. |

**Recommendation:**
- Publish each data version as a GitHub Release asset, which gives a public, citable, share-alike-compliant distribution.
- Mirror it on the backend host under `/data/`.
- The manifest lists both URLs; clients try the backend first, then GitHub, and verify the SHA-256.

## 7. Open source or private backend (undecided, [memory://12](memory://12))

The design works either way:
- No secret lives in code. Configuration comes from environment variables: DB URL, the Apple `.p8` key for the client secret and token revocation, the session-signing key, Google client IDs.
- The protocol is public anyway, because the open-source clients implement it. Its specification is in this repository ([sync.md](sync.md), this file).
- **If open:** `backend/` in the monorepo ([overview.md](overview.md)); self-hosting becomes possible.
- **If private:** a separate private repository. The monorepo keeps only the protocol docs and the shared fixtures.

## 8. Decisions to confirm (owner list)

| # | Proposal | Main alternatives |
|---|---|---|
| B1 | Kotlin + Ktor 3 on the JVM | Go; Swift (Hummingbird/Vapor); TypeScript |
| B2 | PostgreSQL | SQLite + Litestream |
| B3 | One small VPS, Docker Compose, no Cloudflare in front | PaaS + managed Postgres; hyperscaler |
| B4 | Hosting location chosen after the owner says where sync must work (§4.1) | — |
| B5 | Dictionary data: GitHub Releases + mirror on the backend host (if download is chosen) | Backend only; CDN |
| B6 | Backend open source: owner's call; the design supports both | — |
