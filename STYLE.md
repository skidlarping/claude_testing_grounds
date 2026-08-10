# Style

## Naming

- Variables: `camelCase`
- Services (Roblox and project-defined): `PascalCase`
- Functions, local or module: `PascalCase`
- Pure string/number constants: `SCREAMING_SNAKE_CASE`
- Player's character model is always named `char`, never `character`

```lua
local ASSET_ID_PREFIX = "rbxassetid://"
local maxRetries = 3

local function CheckOwnership(player: Player, gamepassId: number): boolean
```

## Services

Always index through `GetService`, never a direct property:

```lua
local Players = game:GetService("Players")
```

Never `game.Players`.

`workspace` is always accessed as the lowercase global, never assigned to a variable:

```lua
workspace.Baseplate.Position
```

Never `local Workspace = game:GetService("Workspace")`.

## Config tables

Once a function or module has 4 or more standalone config-style variables, they collapse into a single `CONFIG` table instead of separate top-level locals.

```lua
local CONFIG = {
	MIN_PLAYERS = 2,
	INTERMISSION_TIME = 10,
	ROUND_TIME = 120,
	ENDING_TIME = 5,
}
```

## Variable ordering

Top of file, in this order:

1. Services (`GetService` calls)
2. Service instances (required modules — other services, controllers, packages)
3. Script instances (folders/instances pulled off the hierarchy, e.g. `ServerScriptService.Services`)
4. Configs / constants

## Connections

Only pre-declare a connection variable if it actually needs to be disconnected later. If it's pre-declared, initialize it as `local x = nil`, never leave it untyped or omit the initializer.

```lua
local renderConnection = nil

local function DisconnectRender()
	if not renderConnection then
		return
	end

	renderConnection:Disconnect()
	renderConnection = nil
end
```

If a connection lives for the module's entire lifetime and is never disconnected, it doesn't get a variable at all — connect it inline in `:Init()`.

## Control flow

No if-trees. Use early returns / guard clauses instead of nesting.

```lua
function RateLimitService:Check(player: Player, key: string): boolean
	local limit = limits[key]

	if not limit then
		warn("Attempted to check an unregistered rate limit key: " .. key)

		return false
	end

	-- continue
end
```

Not:

```lua
function RateLimitService:Check(player: Player, key: string): boolean
	local limit = limits[key]

	if limit then
		-- continue
	else
		warn("Attempted to check an unregistered rate limit key: " .. key)

		return false
	end
end
```

## Spacing

Blank line between distinct logical blocks within a function — separate variable assignments, loops, conditionals, and guards from each other, even if short.

```lua
local record = GetRecord(player, key)

if os.clock() - record.StartTime >= limit.Window then
	record.Count = 0
	record.StartTime = os.clock()
end

if record.Count >= limit.MaxCalls then
	return false
end

record.Count += 1

return true
```

## Numbers

Never write a leading zero before a decimal point. `.05`, not `0.05`. Exception: the value `0` itself is written as `0`, not `.0`.

## Comments

None, except top-of-file directives (e.g. `--!strict`). Code should be self-explanatory through naming; no inline or block comments explaining logic.

## Structure

Every service and controller exposes `:Init()`, and only `:Init()` — no other lifecycle method is called externally. `server/init.server.luau` and `client/init.client.luau` are the only places `:Init()` is ever called from, looping their respective folder's children.

A module never states its own script type (Script/LocalScript/ModuleScript) or where it's placed in the hierarchy — that's entirely owned by `default.project.json` and the folder it's dropped into, not by the file's contents.

