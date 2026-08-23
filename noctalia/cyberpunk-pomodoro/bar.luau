--!nonstrict
-- Cyberpunk Pomodoro Bar Widget — the [[widget]] entry.
--
-- Shows the Pomodoro state in the bar:
-- - Hourglass icon when idle
-- - Phase + countdown when running
-- - Click to open panel

local STATE = "IDLE"
local formattedTime = "00:00"
local sessions = 0
local isVertical = false

--------------------------------------------------------------------------------
-- Color Palette
--------------------------------------------------------------------------------
local C = {
    work = "#ff0055",      -- neon pink
    break_ = "#00ff66",    -- green
    longBreak = "#00ffff", -- cyan
    paused = "#ffee00",    -- yellow
    idle = "#556677",      -- dim
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function getPhaseColor()
    if STATE == "WORK" then
        return C.work
    elseif STATE == "SHORT_BREAK" then
        return C.break_
    elseif STATE == "LONG_BREAK" then
        return C.longBreak
    elseif STATE == "PAUSED" then
        return C.paused
    end
    return C.idle
end

local function getPhaseIcon()
    if STATE == "WORK" then
        return "focus"
    elseif STATE == "SHORT_BREAK" or STATE == "LONG_BREAK" then
        return "coffee"
    elseif STATE == "PAUSED" then
        return "pause"
    end
    return "hourglass"
end

local function getPhaseLabel()
    if STATE == "WORK" then
        return "FOCUS"
    elseif STATE == "SHORT_BREAK" then
        return "BREAK"
    elseif STATE == "LONG_BREAK" then
        return "LONG"
    elseif STATE == "PAUSED" then
        return "PAUSED"
    end
    return ""
end

--------------------------------------------------------------------------------
-- Render
--------------------------------------------------------------------------------
local function render()
    local phaseColor = getPhaseColor()

    if isVertical then
        -- Vertical bar: just icon + time
        barWidget.render(ui.column({ align = "center" }, {
            ui.glyph({ name = getPhaseIcon(), color = phaseColor }),
            ui.label({
                text = STATE ~= "IDLE" and formattedTime or "",
                fontSize = 10,
                fontWeight = "bold",
                color = phaseColor,
            }),
        }))
    else
        -- Horizontal bar: icon + label + time + sessions
        if STATE == "IDLE" then
            barWidget.render(ui.row({ gap = 6, align = "center" }, {
                ui.glyph({ name = "hourglass", color = C.idle }),
            }))
        else
            barWidget.render(ui.row({ gap = 6, align = "center" }, {
                ui.glyph({ name = getPhaseIcon(), color = phaseColor }),
                ui.label({
                    text = getPhaseLabel(),
                    fontSize = 11,
                    fontWeight = "bold",
                    color = phaseColor,
                }),
                ui.label({
                    text = formattedTime,
                    fontSize = 11,
                    fontWeight = "bold",
                    color = phaseColor,
                }),
                ui.label({
                    text = "[" .. sessions .. "]",
                    fontSize = 9,
                    color = "#00ffff",
                }),
            }))
        end
    end
end

--------------------------------------------------------------------------------
-- Click Handler
--------------------------------------------------------------------------------
function onClick()
    noctalia.togglePanel("il1v3y/cyberpunk-pomodoro:panel")
end

--------------------------------------------------------------------------------
-- Update
--------------------------------------------------------------------------------
function update()
    isVertical = barWidget.isVertical()
    render()
end

--------------------------------------------------------------------------------
-- State Watchers
--------------------------------------------------------------------------------
noctalia.state.watch("cyberpunk-pomodoro.state", function(value)
    STATE = value or "IDLE"
    render()
end)

noctalia.state.watch("cyberpunk-pomodoro.formatted", function(value)
    formattedTime = value or "00:00"
    if STATE ~= "IDLE" then
        render()
    end
end)

noctalia.state.watch("cyberpunk-pomodoro.sessions", function(value)
    sessions = value or 0
    render()
end)

--------------------------------------------------------------------------------
-- Initial State
--------------------------------------------------------------------------------
STATE = noctalia.state.get("cyberpunk-pomodoro.state") or "IDLE"
formattedTime = noctalia.state.get("cyberpunk-pomodoro.formatted") or "00:00"
sessions = noctalia.state.get("cyberpunk-pomodoro.sessions") or 0

render()
