--!nonstrict
-- Cyberpunk Pomodoro Service — the headless [[service]] entry.
--
-- Manages the Pomodoro state machine:
-- - WORK (25 min default)
-- - SHORT_BREAK (5 min default)
-- - LONG_BREAK (15 min default, after 4 work sessions)
--
-- State is shared via noctalia.state for other entries to consume.

noctalia.setUpdateInterval(1000) -- tick every second

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------
local WORK_DURATION = 25 * 60        -- 25 minutes
local SHORT_BREAK_DURATION = 5 * 60  -- 5 minutes
local LONG_BREAK_DURATION = 15 * 60  -- 15 minutes
local SESSIONS_BEFORE_LONG_BREAK = 4

--------------------------------------------------------------------------------
-- State Keys
--------------------------------------------------------------------------------
local STATE_KEY = "cyberpunk-pomodoro.state"
local REMAINING_KEY = "cyberpunk-pomodoro.remaining"
local DURATION_KEY = "cyberpunk-pomodoro.duration"
local FORMATTED_KEY = "cyberpunk-pomodoro.formatted"
local SESSIONS_KEY = "cyberpunk-pomodoro.sessions"
local CMD_KEY = "cyberpunk-pomodoro.cmd"

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function formatTime(seconds)
    local m = seconds // 60
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

--------------------------------------------------------------------------------
-- Initialize State
--------------------------------------------------------------------------------
noctalia.state.set(STATE_KEY, "IDLE")
noctalia.state.set(REMAINING_KEY, 0)
noctalia.state.set(DURATION_KEY, 0)
noctalia.state.set(FORMATTED_KEY, "00:00")
noctalia.state.set(SESSIONS_KEY, 0)

--------------------------------------------------------------------------------
-- State Watchers
--------------------------------------------------------------------------------
noctalia.state.watch(REMAINING_KEY, function(value)
    noctalia.state.set(FORMATTED_KEY, formatTime(value))
end)

noctalia.state.watch(CMD_KEY, function(cmd)
    local actions = {
        START = function()
            local state = noctalia.state.get(STATE_KEY)
            local remaining = noctalia.state.get(REMAINING_KEY)

            if state == "IDLE" then
                -- Start a new work session
                noctalia.state.set(STATE_KEY, "WORK")
                noctalia.state.set(REMAINING_KEY, WORK_DURATION)
                noctalia.state.set(DURATION_KEY, WORK_DURATION)
            elseif state == "PAUSED" and remaining > 0 then
                -- Resume from pause
                noctalia.state.set(STATE_KEY, "RUNNING")
            end
        end,

        PAUSE = function()
            local state = noctalia.state.get(STATE_KEY)
            if state == "WORK" or state == "SHORT_BREAK" or state == "LONG_BREAK" then
                noctalia.state.set(STATE_KEY, "PAUSED")
            end
        end,

        RESET = function()
            noctalia.state.set(STATE_KEY, "IDLE")
            noctalia.state.set(REMAINING_KEY, 0)
            noctalia.state.set(DURATION_KEY, 0)
        end,

        SKIP = function()
            local state = noctalia.state.get(STATE_KEY)
            if state == "WORK" or state == "SHORT_BREAK" or state == "LONG_BREAK" then
                -- Force completion by setting remaining to 0
                noctalia.state.set(REMAINING_KEY, 0)
            end
        end,
    }

    local action = actions[cmd]
    if action then
        action()
    else
        noctalia.log("Unknown command: " .. tostring(cmd))
    end

    -- Clear command after processing
    noctalia.state.set(CMD_KEY, nil)
end)

--------------------------------------------------------------------------------
-- Update Loop
--------------------------------------------------------------------------------
function update()
    local state = noctalia.state.get(STATE_KEY)
    local remaining = noctalia.state.get(REMAINING_KEY)

    if state == "WORK" or state == "SHORT_BREAK" or state == "LONG_BREAK" then
        if remaining > 0 then
            noctalia.state.set(REMAINING_KEY, remaining - 1)
        else
            -- Phase completed
            if state == "WORK" then
                local sessions = noctalia.state.get(SESSIONS_KEY) + 1
                noctalia.state.set(SESSIONS_KEY, sessions)

                if sessions % SESSIONS_BEFORE_LONG_BREAK == 0 then
                    -- Long break
                    noctalia.state.set(STATE_KEY, "LONG_BREAK")
                    noctalia.state.set(REMAINING_KEY, LONG_BREAK_DURATION)
                    noctalia.state.set(DURATION_KEY, LONG_BREAK_DURATION)
                    noctalia.notify("Pomodoro", "Long break time! Relax for 15 minutes.")
                else
                    -- Short break
                    noctalia.state.set(STATE_KEY, "SHORT_BREAK")
                    noctalia.state.set(REMAINING_KEY, SHORT_BREAK_DURATION)
                    noctalia.state.set(DURATION_KEY, SHORT_BREAK_DURATION)
                    noctalia.notify("Pomodoro", "Short break! Take 5 minutes.")
                end
            else
                -- Break completed, back to work
                noctalia.state.set(STATE_KEY, "WORK")
                noctalia.state.set(REMAINING_KEY, WORK_DURATION)
                noctalia.state.set(DURATION_KEY, WORK_DURATION)
                noctalia.notify("Pomodoro", "Break over! Back to work.")
            end
        end
    end
end
