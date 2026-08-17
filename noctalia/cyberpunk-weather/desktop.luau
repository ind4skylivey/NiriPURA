--!nonstrict
-- Cyberpunk Weather Desktop Widget v2 - Improved Visual

--------------------------------------------------------------------------------
-- Layout Constants - MAXIMUM
--------------------------------------------------------------------------------
local WIDGET_WIDTH = 700
local PADDING = 30

--------------------------------------------------------------------------------
-- Cyberpunk Color Palette - HIGH INTENSITY
--------------------------------------------------------------------------------
local C = {
    bg = "#05050a",
    border = "#ff0055",
    primary = "#ff0055",    -- NEON PINK/RED
    secondary = "#00ffff",   -- ELECTRIC CYAN
    accent = "#ff00ff",     -- HOT MAGENTA
    text = "#ffffff",
    textDim = "#8888aa",
    warning = "#ffee00",     -- BRIGHT YELLOW
    success = "#00ff66",    -- NEON GREEN
    thailand = "#00eeff",  -- VIBRANT CYAN
    uk = "#ff1144",        -- INTENSE RED
}

--------------------------------------------------------------------------------
-- Runtime State
--------------------------------------------------------------------------------
local locations = {
    {
        city = "Bangkok",
        country = "THAILAND",
        temp = 0,
        humidity = 0,
        condition = "Loading",
        icon = "sun",
        color = C.thailand,
    },
    {
        city = "London",
        country = "UNITED KINGDOM",
        temp = 0,
        humidity = 0,
        condition = "Loading",
        icon = "cloud",
        color = C.uk,
    },
}

local tick = 0

--------------------------------------------------------------------------------
-- Weather Icons with good glyphs
--------------------------------------------------------------------------------
local function getWeatherIcon(condition, isNight)
    local iconMap = {
        ["Clear"] = { glyph = isNight and "moon" or "sun", color = C.warning },
        ["Mainly Clear"] = { glyph = isNight and "moon" or "sun", color = C.warning },
        ["Partly Cloudy"] = { glyph = isNight and "cloud-moon" or "cloud-sun", color = C.warning },
        ["Overcast"] = { glyph = "cloud", color = C.textDim },
        ["Foggy"] = { glyph = "cloud-fog", color = C.textDim },
        ["Light Drizzle"] = { glyph = "cloud-rain", color = C.secondary },
        ["Moderate Drizzle"] = { glyph = "cloud-rain", color = C.secondary },
        ["Slight Rain"] = { glyph = "cloud-rain", color = C.secondary },
        ["Moderate Rain"] = { glyph = "cloud-rain", color = C.secondary },
        ["Heavy Rain"] = { glyph = "cloud-rain", color = C.primary },
        ["Rain Showers"] = { glyph = "cloud-rain", color = C.secondary },
        ["Thunderstorm"] = { glyph = "cloud-lightning", color = C.warning },
        ["Snow"] = { glyph = "snowflake", color = C.secondary },
        ["Unknown"] = { glyph = "cloud", color = C.textDim },
    }
    return iconMap[condition] or { glyph = "cloud", color = C.textDim }
end

--------------------------------------------------------------------------------
-- UI Helpers
--------------------------------------------------------------------------------
local function lbl(text, size, color, bold)
    return ui.label({
        text = text or "",
        fontSize = size,
        fontWeight = bold and "bold" or "normal",
        color = color or C.text,
        fontFamily = "Doom Mono",
        textAlign = "center",
    })
end

local function small(text, size, color)
    return ui.label({
        text = text or "",
        fontSize = size or 14,
        color = color or C.textDim,
        fontFamily = "Doom Mono",
        textAlign = "center",
    })
end

local function line(color, opacity)
    return ui.box({
        height = 1,
        fill = color or C.border,
        opacity = opacity or 0.4,
    })
end

local function spacer(h)
    return ui.box({ height = h or 6 })
end

--------------------------------------------------------------------------------
-- Render single location
--------------------------------------------------------------------------------
local function renderLoc(loc, idx)
    local iconData = getWeatherIcon(loc.condition, false)
    local glow = 0.5 + 0.5 * math.sin(tick * 0.2 + idx * 3)  -- More dramatic pulse

    return ui.column({
        gap = 6,
        align = "center",
        minWidth = 250,
    }, {
        -- Country flag/name with glow bars
        ui.row({ gap = 8, align = "center" }, {
            ui.box({ width = 50, height = 5, fill = loc.color, opacity = glow }),
            lbl(loc.country, 20, loc.color, true),
            ui.box({ width = 50, height = 5, fill = loc.color, opacity = glow }),
        }),

        spacer(14),

        -- City name - MASSIVE
        ui.label({
            text = string.upper(loc.city),
            fontSize = 56,
            fontWeight = "bold",
            color = C.text,
            fontFamily = "Doom Mono",
            textAlign = "center",
        }),

        spacer(14),

        -- Weather icon - BIG
        ui.glyph({
            name = iconData.glyph,
            size = 80,
            color = iconData.color,
        }),

        spacer(14),

        -- Condition - BIGGER
        lbl(string.upper(loc.condition), 30, loc.color, true),

        spacer(18),

        -- Temperature - HUGE
        ui.label({
            text = string.format("%.0f°C", loc.temp),
            fontSize = 130,
            fontWeight = "bold",
            color = C.primary,
            fontFamily = "Doom Mono",
            textAlign = "center",
        }),

        spacer(14),

        -- Humidity
        ui.row({ gap = 8, align = "center" }, {
            ui.glyph({ name = "droplet", size = 24, color = loc.color }),
            small(loc.humidity .. "%", 24, C.textDim),
        }),
    })
end

--------------------------------------------------------------------------------
-- Main render
--------------------------------------------------------------------------------
local function render()
    local glowPulse = 0.6 + 0.4 * math.sin(tick * 0.1)

    desktopWidget.render(ui.column({
        gap = 10,
        align = "center",
        justify = "center",
        minWidth = WIDGET_WIDTH,
        padding = PADDING,
    }, {
        -- ═══ HEADER ═══
        ui.row({ gap = 10, align = "center" }, {
            ui.box({ width = 120, height = 5, fill = C.primary, opacity = 0.4 + 0.6 * glowPulse }),
            lbl("[ GLOBAL WEATHER MONITOR ]", 18, C.primary, true),
            ui.box({ width = 120, height = 5, fill = C.primary, opacity = 0.4 + 0.6 * glowPulse }),
        }),

        spacer(4),
        line(C.border, 0.6),
        spacer(12),

        -- ═══ LOCATIONS ═══
        ui.row({ gap = 40, align = "center", justify = "center" }, {
            renderLoc(locations[1], 0),

            -- Vertical divider
            ui.column({ gap = 0, align = "center" }, {
                line(C.primary, 0.3),
                spacer(8),
                ui.box({ width = 5, height = 280, fill = C.primary, opacity = 0.3 }),
                spacer(8),
                line(C.primary, 0.3),
            }),

            renderLoc(locations[2], 1),
        }),

        spacer(12),
        line(C.border, 0.6),
        spacer(8),

        -- ═══ FOOTER ═══
        ui.row({ gap = 10, align = "center", justify = "center" }, {
            lbl("[ LIVE ]", 12, C.success, true),
            ui.box({ width = 40, height = 3, fill = C.success, opacity = 0.7 }),
            small("open-meteo.com", 12, C.textDim),
            ui.box({ width = 40, height = 3, fill = C.success, opacity = 0.7 }),
            lbl("[ AUTO ]", 12, C.secondary, true),
        }),
    }))
end

--------------------------------------------------------------------------------
-- Update loop
--------------------------------------------------------------------------------
function update()
    noctalia.setUpdateInterval(100)
    tick = tick + 1

    -- Bangkok (index 0)
    locations[1].city = noctalia.state.get("weather.city_0") or "Bangkok"
    locations[1].country = noctalia.state.get("weather.country_0") or "THAILAND"
    locations[1].temp = noctalia.state.get("weather.temp_0") or 0
    locations[1].humidity = noctalia.state.get("weather.humidity_0") or 0
    locations[1].condition = noctalia.state.get("weather.condition_0") or "Loading"
    locations[1].icon = noctalia.state.get("weather.icon_0") or "sun"

    -- London (index 1)
    locations[2].city = noctalia.state.get("weather.city_1") or "London"
    locations[2].country = noctalia.state.get("weather.country_1") or "UNITED KINGDOM"
    locations[2].temp = noctalia.state.get("weather.temp_1") or 0
    locations[2].humidity = noctalia.state.get("weather.humidity_1") or 0
    locations[2].condition = noctalia.state.get("weather.condition_1") or "Loading"
    locations[2].icon = noctalia.state.get("weather.icon_1") or "cloud"

    render()
end

noctalia.state.watch("weather.tick", function()
    render()
end)

update()
