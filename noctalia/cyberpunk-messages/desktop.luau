--!nonstrict
-- Cyberpunk Messages Widget - Hacker Style

local WIDGET_WIDTH = 520
local PADDING = 28

--------------------------------------------------------------------------------
-- Color Palette
--------------------------------------------------------------------------------
local C = {
    bg = "#020204",
    border = "#ff0055",
    primary = "#ff0055",
    secondary = "#00ffff",
    accent = "#ff00ff",
    text = "#ffffff",
    textDim = "#556677",
    green = "#00ff66",
    yellow = "#ffee00",
}

--------------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------------
local MESSAGES = {
    "> Initializing...",
    "> Scanning networks...",
    "> Compiling dreams...",
    "> Accessing mainframe...",
    "> Bypassing firewalls...",
    "> Decrypting secrets...",
    "> Loading vector...",
    "> Connecting to Zero...",
    "> Overriding protocols...",
    "> Trace complete...",
}

local CURRENT_MESSAGE = 1
local DISPLAY_TEXT = ""
local CHAR_INDEX = 0
local LAST_SWITCH_TIME = 0   -- os.time() of last message switch
local LAST_CHAR_CLOCK = 0    -- os.clock() of last char typed
local SWITCH_INTERVAL = 4    -- seconds between messages
local CHARS_PER_SECOND = 25  -- typewriter speed

--------------------------------------------------------------------------------
-- Personal Tagline
--------------------------------------------------------------------------------
local TAGLINE = "The Wired isn't an upper layer of the real world."

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
-- Typewriter Effect
--------------------------------------------------------------------------------
local function updateTypewriter()
    local nowTime = os.time()
    local nowClock = os.clock()

    -- Message switch: every SWITCH_INTERVAL seconds
    if nowTime - LAST_SWITCH_TIME >= SWITCH_INTERVAL then
        LAST_SWITCH_TIME = nowTime
        LAST_CHAR_CLOCK = nowClock
        CHAR_INDEX = 0
        CURRENT_MESSAGE = CURRENT_MESSAGE + 1
        if CURRENT_MESSAGE > #MESSAGES then
            CURRENT_MESSAGE = 1
        end
    end

    local fullMsg = MESSAGES[CURRENT_MESSAGE]

    -- Typewriter: CHARS_PER_SECOND chars per second, ~2-3 per 100ms tick
    local charInterval = 1 / CHARS_PER_SECOND
    if CHAR_INDEX < #fullMsg then
        if nowClock - LAST_CHAR_CLOCK >= charInterval then
            LAST_CHAR_CLOCK = nowClock
            CHAR_INDEX = CHAR_INDEX + 1
            DISPLAY_TEXT = fullMsg:sub(1, CHAR_INDEX) .. "▊"  -- ▊ = blinking cursor
        end
    else
        DISPLAY_TEXT = fullMsg
    end
end

--------------------------------------------------------------------------------
-- Main Render
--------------------------------------------------------------------------------
local function render()
    local now = os.clock()
    local tick = math.floor(now)
    local glow = 0.4 + 0.6 * math.sin(now * 2.5)

    -- Update typewriter
    updateTypewriter()

    desktopWidget.render(ui.column({
        gap = 12,
        align = "center",
        justify = "center",
        minWidth = WIDGET_WIDTH,
        padding = PADDING,
    }, {
        -- ═══ HEADER ═══
        ui.row({ gap = 10, align = "center" }, {
            ui.box({ width = 80, height = 4, fill = C.primary, opacity = glow }),
            ui.row({ gap = 4 }, {
                ui.box({ width = 4, height = 4, fill = C.accent, opacity = glow }),
                lbl("[ SYSTEM ]", 22, C.primary, true),
                ui.box({ width = 4, height = 4, fill = C.accent, opacity = glow }),
            }),
            ui.box({ width = 80, height = 4, fill = C.primary, opacity = glow }),
        }),

        spacer(10),

        -- ═══ TERMINAL MESSAGE ═══
        ui.column({ gap = 6, align = "center" }, {
            -- Cursor blink effect
            ui.box({ height = 2, width = math.random(100, 300), fill = C.green, opacity = 0.3 + 0.3 * math.sin(now * 5) }),

            spacer(8),

            lbl(DISPLAY_TEXT, 24, C.green, true),

            spacer(4),

            -- Blinking cursor
            ui.row({ gap = 2, align = "center" }, {
                lbl("█", 20, C.green, false),
            }),
        }),

        spacer(12),

        sep(C.border, 0.5),

        spacer(14),

        -- ═══ PERSONAL TAGLINE ═══
        ui.column({ gap = 8, align = "center" }, {
            ui.row({ gap = 6, align = "center" }, {
                ui.box({ width = 30, height = 3, fill = C.secondary, opacity = glow * 0.6 }),
                lbl("[ PERSONAL ]", 14, C.secondary, true),
                ui.box({ width = 30, height = 3, fill = C.secondary, opacity = glow * 0.6 }),
            }),

            spacer(10),

            -- Tagline con estilo
            ui.column({
                align = "center",
                padding = 12,
            }, {
                lbl(TAGLINE, 22, C.text, true),
            }),
        }),

        spacer(12),

        sep(C.border, 0.5),

        spacer(8),

        -- ═══ FOOTER ═══
        ui.row({ gap = 8, align = "center" }, {
            ui.box({ width = 40, height = 3, fill = C.green, opacity = glow * 0.6 }),
            lbl("[ LIVE ]", 12, C.green, true),
            ui.box({ width = 40, height = 3, fill = C.green, opacity = glow * 0.6 }),
            lbl("│", 10, C.textDim, false),
            ui.box({ width = 40, height = 3, fill = C.secondary, opacity = glow * 0.6 }),
            lbl("[ " .. tick .. "s ]", 12, C.secondary, true),
            ui.box({ width = 40, height = 3, fill = C.secondary, opacity = glow * 0.6 }),
        }),
    }))
end

--------------------------------------------------------------------------------
-- Update Loop
--------------------------------------------------------------------------------
function update()
    noctalia.setUpdateInterval(100)
    render()
end

-- Initial kickoff
update()
