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

## Session: LoggingService creation

### Path
`src/services/LoggingService.luau`, same Rojo mapping as every other
service.

### Scope
Deliberately has zero dependencies, no `Net`, no `Signal`, no `DataService`,
so it's the same kind of fully standalone, reusable-in-any-project module as
`DataService`. Three public methods: `Print`, `Warn`, `Error`, all taking
`(source: string, message: string)`. All formatting goes through one
`Format(source, level, message)` helper that prefixes
`[HH:MM:SS] [LEVEL] [source]` onto the message.

### Error handling decision
`Error` calls Luau's `warn()`, not `error()`. Actually throwing would unwind
the caller's stack, which is wrong for a logging call, a service reporting
"this failed" shouldn't also interrupt its own control flow just by logging
it. `Warn` and `Error` both go through `warn()` so they render the same way
in the output, the `[LEVEL]` tag in the formatted string is what
distinguishes them, since color alone doesn't.

### No webhook
Explicitly scoped out per Brax, error-level logs stay server-side only, no
Discord or external integration.

### Relationship to the existing `ServerLog` remote
Not touched. The `ServerLog` `Net` remote in `init.server.luau` /
`init.client.luau` is a separate, narrower thing, it broadcasts service
init success/failure to clients specifically for dev visibility during
startup. `LoggingService` doesn't replicate to clients at all, it's a
server-console-only formatting wrapper. Worth considering later whether
`init.server.luau`'s ad hoc `ServerLog:FireAllClients` calls should route
through `LoggingService` too, but that would mean giving `LoggingService` a
client-replication mode, out of scope for what was asked this session.

### Not done / open items
- No log history/buffering, DataStore-backed log retrieval, or Discord
  webhook, all explicitly out of scope for now.
- No integration into existing services yet (DataService, CurrencyService,
  etc. still use local `warn()` calls directly), migrating those over is a
  future cleanup, not done automatically here to avoid an unrelated diff.

Diff pushed, awaiting review.

## Session: RateLimitService creation

### Path
`src/services/RateLimitService.luau`, same Rojo mapping as every other
service.

### Scope
Standalone like `LoggingService`, only depends on `Players`, no `Net`,
`Signal`, or `DataService`. Meant to be called from inside a remote handler
as the first line, before any other logic runs, in any project.

### Design
Fixed-window counter per `(player, key)`. A "key" is whatever string the
caller wants to rate limit under, typically a remote name. Two methods:
- `RateLimitService:Register(key, maxCalls, window)`, called once (e.g. from
  the owning service's `Init`) to define the limit for that key.
- `RateLimitService:Check(player, key): boolean`, called on every attempt.
  Returns `true` and counts the call if the player is still under
  `maxCalls` within the current `window` (seconds), `false` otherwise. When
  the window has elapsed since `StartTime`, the count resets.

### Fail-closed on unregistered keys
`Check` against a key nobody called `Register` for returns `false` and
`warn()`s, rather than defaulting to allowed. This was a deliberate choice
over fail-open: a security-facing service should break loudly and obviously
during testing if setup was forgotten, not silently pass every call through
unlimited. Fail-open would only show up as a problem once someone actually
exploits the gap.

### Cleanup
`Players.PlayerRemoving` clears `records[player]` entirely, connected
inline in `Init` since there's nothing to disconnect later.

### Usage pattern
Not enforced automatically, still relies on each remote handler actually
calling `Check` first. Discussed with Brax as the known limitation, this
service closes the "someone forgets a per-remote debounce" gap and makes
limits centrally readable/tunable, but doesn't make calling it mandatory.
Intended pattern for future remotes:
```
RateLimitService:Register("SpareOrKill", 5, 10) -- once, e.g. in Init

-- in the remote handler, first line:
if not RateLimitService:Check(player, "SpareOrKill") then
	return
end
```

### Not done / open items
- No integration into any existing remote yet, `PlayLocalSound` and
  `ServerLog` are both effectively low-risk (one plays a harmless sound,
  the other is server-to-client only) so neither was retrofitted this
  session.
- No burst-vs-sustained distinction (e.g. token bucket), fixed window can
  allow up to `2x maxCalls` in quick succession right at a window boundary.
  Not addressed since it's a minor edge case for the intended use (blocking
  gross spam, not precise rate shaping) and would add complexity against
  the "lightweight and simple" goal.
- No per-key default (e.g. auto-register with a fallback limit), by design,
  see fail-closed reasoning above.

Diff pushed, awaiting review.

## Session: AnalyticsService creation

### Path
`src/services/AnalyticsService.luau`, same Rojo mapping as every other
service.

### Scope
Thin wrapper around Roblox's built-in `game:GetService("AnalyticsService")`,
aliased to `RobloxAnalyticsService` to avoid the name collision (same
pattern `SoundService.luau` used with `RobloxSoundService`). Standalone,
only depends on `HttpService` and `Players`, no other services. Covers
onboarding funnels, recurring funnels, economy events, and progression
events, the four event types Roblox's own service exposes for exactly this
purpose.

### Recurring funnel session handling
`LogFunnelStepEvent` needs a `funnelSessionId` to distinguish separate
passes through a recurring funnel (e.g. a player opening the shop multiple
times in one session). Rather than auto-generating a session id lazily on
first use, per session (which would incorrectly treat a player's entire
play session as one shop visit), `StartFunnel(player, funnelName)` must be
called explicitly whenever the funnel actually begins (shop opened, round
started), generating a fresh `HttpService:GenerateGUID(false)` each time.
`LogFunnelStep` then looks up the current session id for that funnel name
and warns + no-ops if `StartFunnel` was never called, rather than silently
logging under a missing or wrong session. Onboarding funnels don't need
this since `LogOnboardingFunnelStepEvent` has no session concept, it's
one-time per player by design.

### Progression events
Used the three convenience methods Roblox already exposes
(`LogProgressionStartEvent` / `LogProgressionCompleteEvent` /
`LogProgressionFailEvent`) instead of wrapping the single enum-based
`LogProgressionEvent`, so callers don't need to know about
`Enum.AnalyticsProgressionType` at all.

### Economy events
`LogEconomyEvent` is a direct passthrough with the same signature Roblox's
version takes (`flowType`, `currencyType`, `endingBalance`, `amount`,
`transactionType`, `itemSku`). Kept as a passthrough rather than a
simplified wrapper since callers (e.g. `CurrencyService`) already have all
of these values on hand when a transaction happens, there's nothing to
hide here. Having it go through this service instead of every other
service calling Roblox's `AnalyticsService` directly keeps one central
place to swap the backend later if an external analytics endpoint is ever
wanted instead.

### Cleanup
`Players.PlayerRemoving` clears `funnelSessions[player]`, same pattern as
`RateLimitService`.

### Constraints carried over from Roblox's own docs, not enforced by this
### module
- Events only actually send from the server in a published, live
  experience, nothing will show up while testing in Studio or in an
  unpublished place.
- Onboarding funnel steps are limited to 1-100 by Roblox.
- Skipped funnel steps are auto-counted as completed by Roblox's side, not
  something this wrapper can or should change.

### Not done / open items
- Not wired into `CurrencyService`, `ProductService`, or `GamepassService`
  yet, those calls need to be added per-game once a specific funnel is
  actually being tracked (e.g. `AnalyticsService:LogEconomyEvent` inside
  `CurrencyService:AddCash`), not done blind here since customFields and
  transaction types are game-specific.
- No `customFields` parameter exposed on any method yet (Roblox's raw
  methods support it), left out for now to keep the surface minimal, add
  per-method as a specific need comes up.
- No ABTestService integration yet (discussed conceptually, not built).

Diff pushed, awaiting review.

## Session: RoundService creation

### Path
`src/services/RoundService.luau`, same Rojo mapping as every other service.

### What "pasteable framework" means here, vs. the other standalone services
`DataService`, `LoggingService`, `RateLimitService`, and `AnalyticsService`
are drop-in-and-just-work, they don't know anything about the game they're
in. `RoundService` can't be that, since "what happens during a round" is
different in every game. Instead it owns just the round *lifecycle* (state
machine + timers) and exposes signals for game-specific services to hook
into, without ever knowing what those services actually do. Pasting it into
a new game means editing `CONFIG` for that game's numbers and connecting
game logic to the signals, no changes to the state machine itself should be
needed.

### State machine
Four states: `Waiting` (not enough players), `Intermission` (counting down
to round start, players can still back out), `InRound` (round active),
`Ending` (post-round, before looping back). Only depends on `Signal`
(already a project package) and `Players`, no `DataService` or anything
game-specific.

### Cancellation via version counter
Countdown loops (`Countdown(duration, version)`) are spawned with the
`currentVersion` at the time they start, and check it after every second of
`task.wait`. `SetState` increments `currentVersion` on every transition, so
if something forces an early transition (an empty server during
`Intermission`, `RoundService:EndRound()` called mid-round), any
in-flight countdown loop from the old state sees a version mismatch and
just stops rather than continuing to run and firing a stale transition
later. Chosen over `task.cancel` on stored thread handles, since a version
check reads clearly next to the state machine logic and avoids needing to
track thread handles alongside every countdown.

### Empty-server handling
Two defaults baked in, since "if nobody's here, don't run a round" applies
to essentially every round-based game: leaving mid-`Intermission` drops
back to `Waiting` immediately if player count falls under
`CONFIG.MIN_PLAYERS` (rather than waiting out the full intermission timer
first), and the last player leaving mid-`InRound` calls
`RoundService:EndRound("Empty")` immediately rather than letting an empty
round run for the full `CONFIG.ROUND_TIME`.

### API surface
- `RoundService.State`, the enum table (`Waiting`/`Intermission`/
  `InRound`/`Ending`), for callers comparing against `GetState()`.
- `RoundService.StateChanged` (Signal), fires `(newState, oldState)`.
- `RoundService.RoundStarting` (Signal), fires when `Intermission` begins,
  for game logic to reset/prep before the round officially starts.
- `RoundService.RoundStarted` (Signal), fires when `InRound` begins, for
  game logic to actually start the mechanic (spawn players, enable damage,
  etc).
- `RoundService.RoundEnded` (Signal), fires `(reason: string?)` when
  `Ending` begins, for game logic to show results/cleanup. `reason` is
  whatever string the game-specific win-condition code passed to
  `EndRound`, or `"TimeUp"`/`"Empty"` for the two built-in cases.
- `RoundService.Tick` (Signal), fires `(state, timeLeft)` once per second
  during both `Intermission` and `InRound`, one signal for both so a
  round-timer UI only has to hook one thing.
- `RoundService:GetState()` / `RoundService:GetTimeLeft()`.
- `RoundService:EndRound(reason: string?)`, the hook a game's win-condition
  service calls to end the round early, no-ops outside `InRound`.
- `RoundService:SkipIntermission()`, forces `Intermission` straight into
  `InRound`, useful for dev testing or a "ready up" mechanic later.

### CONFIG (the part meant to be edited per game)
`MIN_PLAYERS` (2), `INTERMISSION_TIME` (10s), `ROUND_TIME` (120s, acts as
both the round's expected length and a safety cap in case a game's
win-condition code never calls `EndRound`), `ENDING_TIME` (5s).

### Not done / open items
- No round history/stats, this is lifecycle only.
- No per-game win condition logic, by design, that's what `RoundStarted`
  and `EndRound` are for.
- Not yet wired into any specific game, next step for whichever project
  uses this is connecting `RoundStarting`/`RoundStarted`/`RoundEnded` to
  that game's own spawn/teleport/UI logic.

Diff pushed, awaiting review.
