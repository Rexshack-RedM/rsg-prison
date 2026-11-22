# Changelog

All notable changes to rsg-prison. Newest first.

## 3.3.1
- Fix: jailing now removes every job through rsg-core's built-in multi-job exports (`GetPlayerJobs` / `RemovePlayerJob`). The old `rsg-multijob` state check never matched, so only the active job was cleared.

## 3.3.0

### Documentation
- `DOCS.md`: added a generated technical reference (dependencies, database, configuration, exports, callbacks, events, commands, items, locales) with code examples, read straight from the source.
