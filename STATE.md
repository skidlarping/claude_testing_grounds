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

Diff pushed, reviewed and merged.

## Session: bug fix

`OnDataLoaded` in CurrencyService was changed (outside this session) to a
single-param signature `(data: any)`, but it's connected to
`DataService.DataLoaded`, which fires `(player, data)`. That meant `data`
inside the handler was actually bound to the `Player` instance, and
`data.Cash` would error on every player load. Restored to a two-param
signature, `(_: Player, data: any)`, since the `player` argument isn't used
in the body.

Diff pushed, reviewed and merged.

## Session: ProductService and GamepassService creation

Both at `src/services/`, same path deviation as the other two.

### Shared pattern
Both services key a table of IDs to handler functions:
`PRODUCT_HANDLERS[productId] = function(player) ... end` and
`GAMEPASS_HANDLERS[gamepassId] = function(player) ... end`. Both tables start
empty, there are no real product/gamepass IDs to register yet, that's on
Brax to fill in once IDs exist. To register a handler, just add an entry to
the relevant table, no other wiring needed.

### ProductService
`ProcessReceipt` looks up the incoming `ProductId` in `PRODUCT_HANDLERS` and
`pcall`s it. If a handler doesn't exist, or the player left, or the player's
data isn't loaded yet (`DataService:Get(player)` returns nil), or the handler
itself errors, `ProcessReceipt` returns `NotProcessedYet` so Roblox retries
the receipt automatically (it keeps retrying across sessions for up to 3
days per Roblox's own retry behavior). Only returns `PurchaseGranted` once
the handler runs without erroring. This means handlers signal failure by
just erroring, no separate return-value contract needed.

The `DataService:Get(player)` preflight matters because downstream calls
(e.g. `CurrencyService:AddCash`) silently `warn()` and no-op on missing data
rather than erroring, so without the preflight a purchase could get marked
`PurchaseGranted` while the actual reward silently failed to apply.

Only one module can set `MarketplaceService.ProcessReceipt` per game, if
another service ever needs to react to receipts, funnel it through this
service's handler table instead of assigning `ProcessReceipt` elsewhere.

### GamepassService
Ownership isn't rechecked on a timer, it's rechecked once per join via
`DataService.DataLoaded` (not `Players.PlayerAdded` directly), so the same
data-not-loaded-yet problem above doesn't bite here either. For every
gamepass with a registered handler, `UserOwnsGamePassAsync` is checked and
the handler runs if owned. A live purchase is caught separately via
`MarketplaceService.PromptGamePassPurchaseFinished`, which also runs the
handler immediately rather than waiting for a rejoin.

Important: unlike ProductService (exactly-once per receipt, enforced by
Roblox), GamepassService's handlers run on every join for as long as the
player owns the pass. Handlers must be written idempotently, permanent
perks should use `Set`-style calls (e.g.
`CurrencyService:SetCashMultiplier`) rather than cumulative `Add`-style
calls, since `Add` would stack further on every rejoin. A true one-time
grant (e.g. a starting cash bonus tied to owning a pass) needs its own
guard, a flag written into the player's persisted data, checked by the
handler before granting, since nothing in GamepassService tracks
"already granted historically" across sessions on its own.

`GamepassService:Owns(player, gamepassId)` is exposed for other services
that just need a cheap ownership check (e.g. a passive multiplier check)
without needing a handler at all, backed by the in-memory cache built on
`DataLoaded` and updated live on purchase.

### Not done / open items
- No actual product/gamepass IDs registered yet, both handler tables are
  empty.
- No `ServerLog` integration, same gap as the other two services.
- `GamepassService:Owns` returns `false` if data hasn't loaded yet
  (`ownedGamepasses[player]` won't exist), callers should be aware ownership
  checks made before `DataLoaded` fires will read as "not owned."

Diff not pushed, awaiting review.

## Session: SoundService creation

### Path
Same deviation as the other services: task requested
`src/server/services/SoundService.luau`, placed at
`src/services/SoundService.luau` to match the actual Rojo mapping in
`default.project.json`. Also added `src/controllers/SoundController.luau`,
required for `PlayLocal` to actually do anything (see below), mapped by
`default.project.json` to `StarterPlayer/StarterPlayerScripts/Controllers`.
This is the first file in that mapping, the folder didn't exist before this
session.

### Global vs local mechanism
Both methods rely on native Roblox behavior rather than any custom
replication or filtering:
- `PlayGlobal` parents a `Sound` instance to the built-in
  `game:GetService("SoundService")`, not `workspace`. A sound parented there
  is non-positional and replicates to every client the same way any other
  instance does, no per-player logic needed on the service's part.
- `PlayLocal` cannot be done server-side at all, only the owning client can
  restrict playback to itself. The server validates the sound id, then fires
  a single-recipient `PlayLocalSound` RemoteEvent (via `Net`, the existing
  networking package, not a new integration) to the target player only.
  `SoundController` on the client receives it and calls the built-in
  `RobloxSoundService:PlayLocalSound(sound)`, which is the native Roblox API
  for playing a sound that only the calling client hears.

### Security
`PlayLocal` uses `RemoteEvent:FireClient(player, ...)`, not
`FireAllClients`, so only the intended player ever receives the payload.
There is no `OnServerEvent` handler anywhere in this feature, the RemoteEvent
is strictly server-to-client, so no client can trigger a sound for another
player or for themselves. Both `PlayGlobal` and `PlayLocal` reject non-number
or non-positive `soundId` values before doing anything else, and always
build the `rbxassetid://` prefix internally rather than accepting an
already-formed string, so callers can't pass arbitrary `SoundId` content.

### Cleanup
`CleanupSound` destroys the server-side `Sound` instance on `Ended`, plus a
`CONFIG.SOUND_LIFETIME` (30s) `task.delay` fallback in case the asset fails
to load and `Ended` never fires. `Destroy()` is idempotent so both paths
firing isn't an issue. The client-side sound in `SoundController` only has
the `Ended` cleanup, no fallback timer, since a failed local sound is a
single small leaked instance on one client rather than a server-wide leak.

### API surface
- `SoundService:PlayGlobal(soundId: number, volume: number?)`, plays a sound
  for every player.
- `SoundService:PlayLocal(player: Player, soundId: number, volume: number?)`,
  plays a sound for one specific player only.
- Volume is optional on both, defaults to `CONFIG.DEFAULT_VOLUME` (1) and is
  clamped to `CONFIG.MAX_VOLUME` (10).

### Not done / open items
- No looping, pitch, or `SoundGroup` support, kept to the minimum the task
  asked for (play locally, play globally).
- No queueing or priority handling if a player receives many `PlayLocal`
  calls in quick succession, each just plays independently.
- No `ServerLog` integration for the invalid-`soundId` warnings, same gap
  noted for the other services, still local `warn()` calls.

Diff pushed, awaiting review.
