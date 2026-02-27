# RemoteGuard

Server-side protection layer for Roblox `RemoteEvent` and `RemoteFunction`.  
Built with [evaera/roblox-lua-promise](https://eryn.io/roblox-lua-promise/).

## Installation

1. Drop the `RemoteGuard` folder into `ServerScriptService` (or `ServerStorage`).
2. Install [roblox-lua-promise](https://eryn.io/roblox-lua-promise/) into `ReplicatedStorage.Packages.Promise`.
3. Require the module from any **server** script:

```lua
local remoteGuard = require(script.core.remoteGuard)
```

- RemoteGuard is server-only. Requiring it on the client will throw an error.

## Quick Start

```lua
local remoteGuard = require(script.core.remoteGuard)

remoteGuard.wrapEvent("SendMessage", {
    perSecLimit = 10,
    banDuration = 30,
    args = {
        { type = "string", required = true  },
        { type = "number", required = true  },
        { type = "boolean", required = false },
    },
}, function(player, message, channel, isWhisper)
    print(player.Name, channel, message)
end)
```

If `"SendMessage"` doesn't exist in `ReplicatedStorage`, RemoteGuard creates it automatically.

## Config Reference

All fields are optional. Unset fields fall back to the defaults in `Constants.lua`.

| Field | Type | Default | Description |

| `name` | `string` | remote.Name | Name used in logs |

| `cooldown` | `number` | `0` | Minimum seconds between **valid** calls. Bad calls (wrong type, missing arg) do **not** reset the cooldown timer. |

| `perSecLimit` | `number` | `10` | Max calls per second (any validity). Exceeding this triggers an immediate ban. |

| `rateLimit` | `number` | `10` | Max **valid** calls within `rateWindow` seconds before ban. |

| `rateWindow` | `number` | `5` | Window in seconds for `rateLimit`. |

| `banDuration` | `number` | `30` | Seconds a player is banned after exceeding `perSecLimit` or `rateLimit`. |

| `timeout` | `number` | `10` | `wrapFunction` only - seconds before the invoke is cancelled and `nil` is returned. |

| `permission` | `function` | `nil` | `function(player): boolean` - return `false` to deny access. |

| `args` | `table` | `nil` | Ordered list of argument schemas (see [Argument Schemas](#argument-schemas)). |

## Argument Schemas

Each entry in `args` describes one argument passed from the client.

```lua
args = {
    { type = "string",  required = true  }, -- arg1: must be a string
    { type = "number",  required = true  }, -- arg2: must be a number
    { type = "boolean", required = false }, -- arg3: optional
}
```

**Supported primitive types:** `"string"`, `"number"`, `"boolean"`, `"table"`, `"any"`

**Nested tables** are validated recursively:

```lua
args = {
    {
        type = {
            itemId   = "string",
            quantity = "number",
            meta = {
                isPremium = "boolean",
            },
        },
        required = true,
    },
}
```

If a nested field has the wrong type, the log will show the exact path:
```
[WARN] Type mismatch: [arg1.meta.isPremium] expected boolean, got string
```

## API

### `remoteGuard.wrapEvent(remote, config, handler)`

Wraps a `RemoteEvent`. `handler(player, ...)` is called only when all checks pass.  
Returns the `RBXScriptConnection` - store it if you need to disconnect later.

`remote` can be a `RemoteEvent` instance **or a string name**. If the remote doesn't exist it is created in `ReplicatedStorage`.

```lua
local conn = remoteGuard.wrapEvent("SendMessage", config, function(player, msg, ch)
    print(player.Name, msg, ch)
end)

-- disconnect later if needed
conn:Disconnect()
```



### `remoteGuard.wrapFunction(remote, config, handler)`

Wraps a `RemoteFunction`. `handler(player, ...)` must return the response value(s).  
The invoke is automatically cancelled after `config.timeout` seconds (default 10s) and returns `nil` to the client.

`remote` can be a `RemoteFunction` instance or a string name.

```lua
remoteGuard.wrapFunction("GetData", {
    cooldown = 1,
    timeout  = 10,
    args = { { type = "string", required = true } },
}, function(player, key)
    return dataStore[key]
end)
```

### `remoteGuard.wrapEventWithReply(remote, replyRemote, config, handler)`

Wraps a `RemoteEvent` and automatically fires a reply back to the client via `replyRemote`.

- On success → `replyRemote:FireClient(player, true, result)`
- On any failure → `replyRemote:FireClient(player, false, reason, extra)`

Both `remote` and `replyRemote` accept instances or string names.

```lua
-- server
remoteGuard.wrapEventWithReply("SubmitScore", "SubmitScoreReply", {
    cooldown = 5,
    args = { { type = "number", required = true } },
}, function(player, score)
    return score * 2
end)

-- client
game.ReplicatedStorage.SubmitScoreReply.OnClientEvent:Connect(function(ok, result, reason)
    if ok then
        print("doubled score:", result)
    else
        print("failed:", reason)
    end
end)
game.ReplicatedStorage.SubmitScore:FireServer(500)
```

### `remoteGuard.ban(player, remoteName, duration?)`

Manually bans a player from a specific remote for `duration` seconds (default 30s).

```lua
remoteGuard.ban(player, "SendMessage", 300)
```


### `remoteGuard.unban(player, remoteName)`

Removes the ban and clears the player's call history for that remote.

```lua
remoteGuard.unban(player, "SendMessage")
```

### `remoteGuard.isBanned(player, remoteName)`

Returns `isBanned: boolean` and optionally `secondsRemaining: number`.

```lua
local banned, left = remoteGuard.isBanned(player, "SendMessage")
if banned then
    print("banned for another", left, "seconds")
end
```

## Validation Pipeline

Every call runs through these checks **in order**. The first failure rejects the Promise and nothing further runs.

```
1. Ban check        - is this player currently banned?
2. Per-second flood - more than perSecLimit calls in the last 1 second? → ban
3. Cooldown         - was the last VALID call too recent?
4. Permission       - does permission(player) return false?
5. Arg type check   - do all arguments match their schemas?
6. Rate-limit       - too many VALID calls in rateWindow? → ban
```

> **Key rule:** only calls that pass steps 1–5 are counted toward the cooldown timer and rate-limit window. Wrong types, missing args, and permission failures are logged and silently dropped - they do not penalise the player's cooldown.

## Log Output

| Level | Trigger | Output |

| `INFO` | Remote auto-created | `[RemoteGuard][INFO] <Name> [server] RemoteEvent not found - created in ReplicatedStorage` |

| `WARN` | Cooldown / bad type / missing arg | `[RemoteGuard][WARN] <SendMessage> [Player1] Cooldown active. 1.4s remaining.` |

| `DENIED` | Permission returned false | `[RemoteGuard][DENIED] <AdminKick> [Player1] Permission denied.` |

| `SPAM` | Flood or rate-limit exceeded | `[RemoteGuard][SPAM] <SendMessage> [Player1] FLOOD DETECTED - 14 calls/sec (limit 10). Banned for 30s!` |

| `BLOCKED` | Call while banned | `[RemoteGuard][BLOCKED] <SendMessage> [Player1] Player is banned. 28s remaining. Stop spamming!` |

| `ERROR` | Handler threw / permission threw | `[RemoteGuard][ERROR] <GetData> [Player1] Handler error: attempt to index nil` |

`SPAM`, `BLOCKED`, and `ERROR` use `warn()`. Everything else uses `print()`.

## Promise Integration

Every validation returns a `Promise`. You can chain it directly if you need custom logic beyond the built-in handler:

```lua
-- manual usage of the validator (advanced)
local Validator = require(script.core.remoteGuard.Validator)

Validator.validate(config, player, args)
    :andThen(function()
        -- passed all checks
    end)
    :catch(function(reason, extra)
        -- reason: "blocked" | "flood" | "cooldown" | "no_permission" | "missing_arg" | "bad_type" | "ratelimit"
        print("rejected:", reason, extra)
    end)
```

## Dependencies

- [evaera/roblox-lua-promise](https://eryn.io/roblox-lua-promise/) - place the ModuleScript at `ReplicatedStorage.Packages.Promise`


