--!nonstrict
-- Cyberpunk Pomodoro Desktop Widget — the [[desktop_widget]] entry.
--
-- Displays the Pomodoro timer with cyberpunk aesthetics:
-- - Large countdown display
-- - Phase indicator (WORK/BREAK/LONG_BREAK)
-- - Progress bar
-- - Control buttons
-- - Session counter

--------------------------------------------------------------------------------
-- Color Palette (Cyberpunk)
--------------------------------------------------------------------------------
local C = {
    bg = "#020204",
    border = "#ff0055",
    primary = "#ff0055",      -- neon pink
    secondary = "#00ffff",    -- cyan
    accent = "#ff00ff",       -- magenta
    text = "#ffffff",
    textDim = "#556677",
    green = "#00ff66",
    yellow = "#ffee00",
    work = "#ff0055",         -- pink for work
    break_ = "#00ff66",       -- green for short break
    longBreak = "#00ffff",    -- cyan for long break
}

--------------------------------------------------------------------------------
-- State Mirror
--------------------------------------------------------------------------------
local STATE = "IDLE"
local remaining = 0
local duration = 0
local formattedTime = "00:00"
local sessions = 0

--------------------------------------------------------------------------------
-- UI Helpers
--------------------------------------------------------------------------------
local function lbl(text, size, color, bold)
    return ui.label({
        text = text or "",
        fontSize = size,
        fontWeight = bold and "bold" or "normal",
        color = color or C.text,
        fontFamily = "JetBrains Mono",
        textAlign = "center",
    })
end

local function sep(color, opacity)
    return ui.box({
        height = 1,
        fill = color or C.border,
        opacity = opacity or 0.4,
    })
end

local function spacer(h)
    return ui.box({ height = h or 8 })
end

--------------------------------------------------------------------------------
-- Phase Color
--------------------------------------------------------------------------------
local function getPhaseColor()
    if STATE == "WORK" then
        return C.work
    elseif STATE == "SHORT_BREAK" then
        return C.break_
    elseif STATE == "LONG_BREAK" then
        return C.longBreak
    elseif STATE == "PAUSED" then
        return C.yellow
    end
    return C.textDim
end

--------------------------------------------------------------------------------
-- Phase Label
--------------------------------------------------------------------------------
local function getPhaseLabel()
    if STATE == "WORK" then
        return "[ FOCUS ]"
    elseif STATE == "SHORT_BREAK" then
        return "[ BREAK ]"
    elseif STATE == "LONG_BREAK" then
        return "[ LONG BREAK ]"
    elseif STATE == "PAUSED" then
        return "[ PAUSED ]"
    elseif STATE == "IDLE" then
        return "[ READY ]"
    end
    return "[ UNKNOWN ]"
end

--------------------------------------------------------------------------------
-- Main Render
--------------------------------------------------------------------------------
local function render()
    local now = os.clock()
    local glow = 0.4 + 0.6 * math.sin(now * 2.5)
    local phaseColor = getPhaseColor()
    local phaseLabel = getPhaseLabel()
    local progress = duration > 0 and remaining / duration or 0

    desktopWidget.render(ui.column({
        gap = 12,
        align = "center",
        justify = "center",
        minWidth = 420,
        padding = 24,
    }, {
        -- ═══ HEADER ═══
        ui.row({ gap = 10, align = "center" }, {
            ui.box({ width = 60, height = 4, fill = C.primary, opacity = glow }),
            ui.row({ gap = 4 }, {
                ui.box({ width = 4, height = 4, fill = C.accent, opacity = glow }),
                lbl("[ POMODORO ]", 20, C.primary, true),
                ui.box({ width = 4, height = 4, fill = C.accent, opacity = glow }),
            }),
            ui.box({ width = 60, height = 4, fill = C.primary, opacity = glow }),
        }),

        spacer(10),

        -- ═══ PHASE INDICATOR ═══
        ui.column({ gap = 6, align = "center" }, {
            ui.box({ height = 2, width = 180, fill = phaseColor, opacity = 0.3 + 0.3 * math.sin(now * 4) }),
            spacer(6),
            lbl(phaseLabel, 22, phaseColor, true),
            spacer(4),
            ui.box({ height = 2, width = 180, fill = phaseColor, opacity = 0.3 + 0.3 * math.sin(now * 4) }),
        }),

        spacer(12),

        -- ═══ TIMER DISPLAY ═══
        ui.column({ gap = 8, align = "center" }, {
            lbl(formattedTime, 56, phaseColor, true),

            -- Progress bar
            ui.progress({
                progress = progress,
                fill = phaseColor,
                width = 280,
                height = 8,
                radius = 4,
            }),
        }),

        spacer(12),

        sep(C.border, 0.5),

        spacer(10),

        -- ═══ SESSION COUNTER ═══
        ui.row({ gap = 8, align = "center" }, {
            ui.box({ width = 40, height = 3, fill = C.secondary, opacity = glow * 0.6 }),
            lbl("[ SESSIONS: " .. sessions .. " ]", 14, C.secondary, true),
            ui.box({ width = 40, height = 3, fill = C.secondary, opacity = glow * 0.6 }),
        }),

        spacer(8),

        -- ═══ CONTROLS ═══
        ui.row({ gap = 12, justify = "center" }, {
            ui.button({
                text = "RESET",
                variant = "destructive",
                onClick = "onReset",
            }),
            ui.button({
                text = STATE == "PAUSED" and "RESUME" or (STATE == "IDLE" and "START" or "PAUSE"),
                variant = STATE == "IDLE" and "primary" or "secondary",
                onClick = "onToggle",
                enabled = STATE ~= "IDLE" or remaining == 0,
            }),
            ui.button({
                text = "SKIP",
                variant = "ghost",
                onClick = "onSkip",
                enabled = STATE == "WORK" or STATE == "SHORT_BREAK" or STATE == "LONG_BREAK",
            }),
        }),

        spacer(8),

        -- ═══ FOOTER ═══
        ui.row({ gap = 8, align = "center" }, {
            ui.box({ width = 30, height = 3, fill = C.green, opacity = glow * 0.6 }),
            lbl("[ LIVE ]", 10, C.green, true),
            ui.box({ width = 30, height = 3, fill = C.green, opacity = glow * 0.6 }),
            lbl("│", 10, C.textDim, false),
            ui.box({ width = 30, height = 3, fill = C.secondary, opacity = glow * 0.6 }),
            lbl("[ " .. math.floor(now) .. "s ]", 10, C.secondary, true),
            ui.box({ width = 30, height = 3, fill = C.secondary, opacity = glow * 0.6 }),
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

noctalia.state.watch("cyberpunk-pomodoro.duration", function(value)
    duration = value or 0
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

--------------------------------------------------------------------------------
-- Initial State
--------------------------------------------------------------------------------
STATE = noctalia.state.get("cyberpunk-pomodoro.state") or "IDLE"
remaining = noctalia.state.get("cyberpunk-pomodoro.remaining") or 0
duration = noctalia.state.get("cyberpunk-pomodoro.duration") or 0
formattedTime = noctalia.state.get("cyberpunk-pomodoro.formatted") or "00:00"
sessions = noctalia.state.get("cyberpunk-pomodoro.sessions") or 0

-- Initial render
render()
