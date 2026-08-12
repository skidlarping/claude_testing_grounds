# claude_testing_grounds

Standalone Roblox backend template built on [Rojo](https://github.com/rojo-rbx/rojo), meant to be copied over as the starting point for new projects. R6 only.

## Setup

```bash
rojo build -o "claude_testing_place.rbxlx"
```

Open `claude_testing_place.rbxlx` in Studio, then run:

```bash
rojo serve
```

## Structure

```
src/
  packages/    Net, Signal, Trove
  services/    ServerScriptService.Services
  controllers/ StarterPlayerScripts.Controllers
  server/      Init script, loads and calls :Init() on every child of Services
  client/      Init script, loads and calls :Init() on every child of Controllers
  shared/      ReplicatedStorage.Shared, holds Data/PlayerData.luau
```

Every service and controller exposes `:Init()`. Nothing outside `server/init.server.luau` or `client/init.client.luau` calls `:Init()` directly, both just loop their respective folder and call it.

## Packages

- **Net** — networking wrapper, remotes are created on demand rather than pre-declared in a Remotes folder
- **Signal** — standalone signal implementation used for all internal service/controller events
- **Trove** — connection/cleanup utility, used where per-character or per-session cleanup is needed (currently `CharacterController`)

## Services

| Service | Responsibility |
|---|---|
| `DataService` | Session-locked player data via `UpdateAsync`, retry logic, `BindToClose`, `SAVE_ENABLED` toggle. Fires `DataLoaded`. |
| `PlayerService` | Gates on `DataService.DataLoaded` / `DataReleasing` to track per-player readiness, join time, and session length. Fires `PlayerReady` / `PlayerLeaving`, single place other services query "is this player fully loaded". |
| `CurrencyService` | `Cash` / `CashMultiplier` get/set/add, built on `DataService`. |
| `ProductService` | Wraps `ProcessReceipt`, dispatches through a `PRODUCT_HANDLERS` table. |
| `GamepassService` | Caches ownership per player, dispatches through `GAMEPASS_HANDLERS`, exposes `Owns()`. |
| `SoundService` | `PlayGlobal` / `PlayLocal`, paired with `SoundController` client-side. |
| `LoggingService` | Timestamped `Print` / `Warn` / `Error`, server-console only, `Error` uses `warn()` to avoid unwinding the caller's stack. |
| `RateLimitService` | Fixed-window per-player rate limiting, `Register` a key then `Check` against it. |
| `AnalyticsService` | Wraps Roblox's `AnalyticsService` for onboarding funnels, economy events, and progression tracking. |

## Controllers

| Controller | Responsibility |
|---|---|
| `SoundController` | Client-side handler for `SoundService`'s `PlayLocalSound` remote. |
| `CameraController` | Owns `workspace.CurrentCamera`, single-owner lock (`Request` / `Release`) so cutscenes and other camera systems can't fight over state, saves/restores default camera state on release. |
| `InputController` | Wraps `ContextActionService` with per-action ownership locking, same lock pattern as `CameraController`, plus `UnbindAll` for cleanup. |
| `CharacterController` | Owns `CharacterAdded`, applies default `WalkSpeed` / `JumpPower`, exposes a shared `Trove` other controllers can add per-character cleanup to. |
| `UIController` | Auto-registers every `Frame` under `PlayerGui.Main.Frames` on `Init`, exposes `Open` / `Close` / `CloseAll` / `GetFrame`, tracks an open-screen stack for back-navigation. Not exclusive, multiple frames can be open at once. |

## Conventions

See `STYLE.md` for code style. See `STATE.md` for a running log of what's been built and why, session by session.
