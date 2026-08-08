# State

## Session: DataService creation

### Path deviation
Task requested `src/server/services/DataService.luau`. Actual Rojo mapping in
`default.project.json` puts the Services folder at `src/services` (top level,
separate from `src/server`, which only maps to the Init script). Placed the
module at `src/services/DataService.luau` to match the real mapping instead of
the literal path given. Also added `src/shared/Data/PlayerData.luau` for the
default data table, matching the established Shared/Data module convention.

### Session-locking decision
Implemented via `UpdateAsync` on load. Each saved record is
`{ SessionLock = { JobId, Time }, Data = {...} }`. On `PlayerAdded`, the
service calls `UpdateAsync` and checks the existing `SessionLock`:
- if it belongs to a different `JobId` and is younger than
  `CONFIG.SESSION_LOCK_TIMEOUT` (30s), the update function errors, which
  fails the attempt and triggers a retry.
- otherwise the lock is overwritten with this server's `JobId` and the
  current time, claiming the session.

If all retries are exhausted, the player is kicked rather than allowed to
play with stale or contested data. This avoids a separate lock datastore and
keeps the lock atomic with the data read via a single `UpdateAsync` call.
Tradeoff: a crashed server (no clean `BindToClose`) locks the player out for
up to 30 seconds before the timeout allows takeover. Not yet handled: no
mechanism to shorten this if a studio/test server crashes repeatedly during
development, may want a lower timeout behind a dev flag later.

### Retry-on-save decision
Both load (`ClaimSession`) and save (`SaveData`) route through a shared
`Attempt` helper: up to `CONFIG.MAX_RETRIES` (3) pcall'd attempts with a fixed
`CONFIG.RETRY_DELAY` (2s) between them. No exponential backoff, kept simple
since DataStore request budget issues are the main failure mode and a fixed
delay is enough to clear most transient throttling. Save failures after all
retries are silently swallowed right now (`SaveData` just returns `false`),
no logging/alerting hooked up yet, that's a TODO.

### Testing toggle
`CONFIG.SAVE_ENABLED` (default `true`) short-circuits `SaveData` to a no-op
success and skips the `BindToClose` save loop entirely when `false`.

### API surface
- `DataService:Get(player)`, returns cached data table or nil if not loaded.
- `DataService:Set(player, data)`, overwrites cached data table.
- `DataService.DataLoaded` (Signal), fires `(player, data)` once claim
  succeeds.
- `DataService.DataReleasing` (Signal), fires `(player, data)` right before
  `PlayerRemoving` save, so other services can flush changes into the data
  table first.

### Not done / open items
- No periodic autosave loop (only saves on leave and `BindToClose`).
- No schema versioning/migration for `PlayerData.Default()` changes.
- No logging of failed saves/kicks to `ServerLog` (the Net remote used in
  `init.server.luau`), currently just silent failure or kick message.
- Consider adding `DataService:Update(player, fn)` for transform-style
  mutation if other services end up needing it.

Diff not pushed, awaiting review.
