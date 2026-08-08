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

Diff pushed, reviewed and merged. `PlayerData.Default()` was later changed by
Brax to use a placeholder value instead of real fields (Level/Experience/Coins
removed, `Placeholder = 1` added).

## Session: CurrencyService creation

### Path
Same deviation as DataService: placed at `src/services/CurrencyService.luau`,
not `src/server/services/`, to match the actual Rojo mapping in
`default.project.json`.

### Data fields
Added `Cash = 0` and `CashMultiplier = 1` to `PlayerData.Default()`, alongside
the existing `Placeholder` field. CurrencyService reads/writes these two
fields directly on the table returned by `DataService:Get(player)` — that
table is the same reference DataService caches internally, so mutating it in
place is sufficient, no `DataService:Set` call needed after each change.

### Multiplier application
`AddCash(player, amount)` multiplies `amount` by the player's current
`CashMultiplier` before adding it to `Cash`. This was the interpretation
that fit the task's own reasoning for keeping `CashMultiplier` floored at 1
("below 1 the cash would just go down") — that only makes sense if earned
cash actually gets scaled by the multiplier somewhere. `SetCash` is a raw,
unscaled overwrite (for deductions, admin/debug tools, etc.) and does not
apply the multiplier.

### Floors
`Cash` is floored at `BASE_CASH` (0) and `CashMultiplier` at
`BASE_CASH_MULTIPLIER` (1) via `math.max` on every `Set`/`Add` call. As
defense against corrupted or manually-edited datastore entries, the service
also hooks `DataService.DataLoaded` and re-clamps both fields (and fills them
in if missing) as soon as data loads, before anything else can touch it.

### No networking
No RemoteEvents/RemoteFunctions and no `Net` usage. All six public methods
(`GetCash`, `SetCash`, `AddCash`, `GetCashMultiplier`, `SetCashMultiplier`,
`AddCashMultiplier`) are plain server-side methods meant to be called by
other services after they've validated whatever triggered the change. If
`DataService:Get(player)` returns nil (data not loaded yet, or player left),
Get-style methods fall back to the base values and Set/Add-style methods
`warn()` and no-op rather than throwing.

### Not done / open items
- No `ServerLog` (Net remote) integration for warnings, still just local
  `warn()` calls — same gap noted for DataService's failed saves.
- No transaction/rollback if a caller adds cash then a save fails right
  after — cash mutation and persistence are decoupled (persistence is
  DataService's job via `BindToClose`/`PlayerRemoving`).
- No upper bound on `Cash` or `CashMultiplier` — only floors exist. Add caps
  later if game design calls for them.

Diff not pushed, awaiting review.

## Session: bug fix

`OnDataLoaded` in CurrencyService was changed (outside this session) to a
single-param signature `(data: any)`, but it's connected to
`DataService.DataLoaded`, which fires `(player, data)`. That meant `data`
inside the handler was actually bound to the `Player` instance, and
`data.Cash` would error on every player load. Restored to a two-param
signature, `(_: Player, data: any)`, since the `player` argument isn't used
in the body.
