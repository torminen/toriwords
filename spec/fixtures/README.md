# Parity fixtures

Shared by iOS, Android and the backend (doc 36 §15, §22). JSON cases per folder:
`normalization/`, `ids/`, `hlc/`, `merge/`, `capture/`, `scheduler/`, `sync/`; schemas in `schema/`.
Swift tests find this folder via `FixtureLocator` (`ios/ToriKit/Tests/ToriTestSupport`), overridable with `TORI_FIXTURES`.
