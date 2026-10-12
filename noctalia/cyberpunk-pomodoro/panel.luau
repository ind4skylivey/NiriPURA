--!nonstrict
-- Cyberpunk Pomodoro Panel — the [[panel]] entry.
--
-- Control panel for the Pomodoro timer with cyberpunk styling.
-- Shows current state, phase info, and control buttons.

--------------------------------------------------------------------------------
-- State Mirror
--------------------------------------------------------------------------------
local STATE = "IDLE"
local remaining = 0
local formattedTime = "00:00"
local sessions = 0

--------------------------------------------------------------------------------
-- Color Palette
--------------------------------------------------------------------------------
local C = {
    primary = "#ff0055",
    secondary = "#00ffff",
    accent = "#ff00ff",
    green = "#00ff66",
    yellow = "#ffee00",
    textDim = "#556677",
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function getPhaseColor()
    if STATE == "WORK" then
        return C.primary
    elseif STATE == "SHORT_BREAK" then
        return C.green
    elseif STATE == "LONG_BREAK" then
        return C.secondary
    elseif STATE == "PAUSED" then
        return C.yellow
    end
    return C.textDim
end

local function getPhaseLabel()
    if STATE == "WORK" then
        return "FOCUS MODE"
    elseif STATE == "SHORT_BREAK" then
        return "SHORT BREAK"
    elseif STATE == "LONG_BREAK" then
        return "LONG BREAK"
    elseif STATE == "PAUSED" then
        return "PAUSED"
    elseif STATE == "IDLE" then
        return "READY"
    end
    return "UNKNOWN"
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------
local function render()
    local phaseColor = getPhaseColor()
    local phaseLabel = getPhaseLabel()
    local btnText = STATE == "PAUSED" and "RESUME" or (STATE == "IDLE" and "START" or "PAUSE")
    local btnVariant = STATE == "IDLE" and "primary" or "secondary"

    panel.render(ui.column({ gap = 16, padding = 20 }, {
        -- Header
        ui.label({
            text = "[ POMODORO TIMER ]",
            fontSize = 18,
            fontWeight = "bold",
            color = C.primary,
            textAlign = "center",
        }),

        -- Separator
        ui.box({ height = 2, fill = C.primary, opacity = 0.5 }),

        -- Phase display
        ui.column({ gap = 8, align = "center" }, {
            ui.label({
                text = phaseLabel,
                fontSize = 16,
                fontWeight = "bold",
                color = phaseColor,
                textAlign = "center",
            }),
            ui.label({
                text = remaining > 0 and formattedTime or "--:--",
                fontSize = 48,
                fontWeight = "bold",
                color = phaseColor,
                textAlign = "center",
            }),
        }),

        -- Separator
        ui.box({ height = 1, fill = C.secondary, opacity = 0.3 }),

        -- Session counter
        ui.row({ gap = 8, justify = "center" }, {
            ui.label({
                text = "Sessions:",
                fontSize = 14,
                color = C.textDim,
            }),
            ui.label({
                text = tostring(sessions),
                fontSize = 16,
                fontWeight = "bold",
                color = C.secondary,
            }),
            ui.label({
                text = "/ 4",
                fontSize = 12,
                color = C.textDim,
            }),
        }),

        -- Spacer
        ui.box({ height = 8 }),

        -- Control buttons
        ui.row({ gap = 12, justify = "center" }, {
            ui.button({
                text = "RESET",
                variant = "destructive",
                onClick = "onReset",
            }),
            ui.button({
                text = btnText,
                variant = btnVariant,
                onClick = "onToggle",
            }),
            ui.button({
                text = "SKIP",
                variant = "ghost",
                onClick = "onSkip",
                enabled = STATE == "WORK" or STATE == "SHORT_BREAK" or STATE == "LONG_BREAK",
            }),
        }),

        -- Spacer
        ui.box({ height = 12 }),

        -- Info
        ui.column({ gap = 4, align = "center" }, {
            ui.label({
                text = "25 min focus • 5 min break",
                fontSize = 11,
                color = C.textDim,
                textAlign = "center",
            }),
            ui.label({
                text = "15 min long break (every 4 sessions)",
                fontSize = 11,
                color = C.textDim,
                textAlign = "center",
            }),
        }),
    }))
end

--------------------------------------------------------------------------------
-- Control Handlers
--------------------------------------------------------------------------------
function onToggle()
    if STATE == "IDLE" then
        noctalia.state.set("cyberpunk-pomodoro.cmd", "START")
    elseif STATE == "PAUSED" then
        noctalia.state.set("cyberpunk-pomodoro.cmd", "START")
    elseif STATE == "WORK" or STATE == "SHORT_BREAK" or STATE == "LONG_BREAK" then
        noctalia.state.set("cyberpunk-pomodoro.cmd", "PAUSE")
    end
end

function onReset()
    noctalia.state.set("cyberpunk-pomodoro.cmd", "RESET")
end

function onSkip()
    noctalia.state.set("cyberpunk-pomodoro.cmd", "SKIP")
end

--------------------------------------------------------------------------------
-- Panel Open Handler
--------------------------------------------------------------------------------
function onOpen(_context)
    STATE = noctalia.state.get("cyberpunk-pomodoro.state") or "IDLE"
    remaining = noctalia.state.get("cyberpunk-pomodoro.remaining") or 0
    formattedTime = noctalia.state.get("cyberpunk-pomodoro.formatted") or "00:00"
    sessions = noctalia.state.get("cyberpunk-pomodoro.sessions") or 0
    render()
end

--------------------------------------------------------------------------------
-- State Watchers
--------------------------------------------------------------------------------
noctalia.state.watch("cyberpunk-pomodoro.state", function(value)
    STATE = value or "IDLE"
    render()
end)

noctalia.state.watch("cyberpunk-pomodoro.remaining", function(value)
    remaining = value or 0
    render()
end)

noctalia.state.watch("cyberpunk-pomodoro.formatted", function(value)
    formattedTime = value or "00:00"
    render()
end)

noctalia.state.watch("cyberpunk-pomodoro.sessions", function(value)
    sessions = value or 0
    render()
end)
