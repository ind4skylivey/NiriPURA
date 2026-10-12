--!nonstrict
-- Cyberpunk Weather Service - Multiple locations: Thailand & UK

local LOCATIONS = {
    { city = "Bangkok", country = "Thailand", lat = 13.75, lon = 100.52 },
    { city = "London", country = "UK", lat = 51.5074, lon = -0.1278 },
}

local UNITS = "metric"
local UPDATE_INTERVAL = 600000 -- 10 minutes

local function getSetting(key, default)
    local v = noctalia.getConfig and noctalia.getConfig(key)
    if type(v) == "string" and v ~= "" then return v end
    return default
end

local function fetchWeatherForLocation(loc)
    local url = string.format(
        "https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m&timezone=auto",
        loc.lat, loc.lon
    )

    noctalia.http({ url = url, follow_redirects = true }, function(res)
        if not res.ok then
            noctalia.log("[cyberpunk-weather] Network error for " .. loc.city)
            return
        end

        local ok, data = pcall(function()
            return noctalia.json.decode(res.body)
        end)

        if not ok or not data or not data.current then
            noctalia.log("[cyberpunk-weather] Parse error for " .. loc.city)
            return
        end

        local current = data.current
        local weatherCodes = {
            [0] = "Clear", [1] = "Mainly Clear", [2] = "Partly Cloudy",
            [3] = "Overcast", [45] = "Foggy", [48] = "Depositing Rime Fog",
            [51] = "Light Drizzle", [53] = "Moderate Drizzle", [55] = "Dense Drizzle",
            [61] = "Slight Rain", [63] = "Moderate Rain", [65] = "Heavy Rain",
            [71] = "Slight Snow", [73] = "Moderate Snow", [75] = "Heavy Snow",
            [80] = "Rain Showers", [81] = "Moderate Showers", [82] = "Violent Showers",
            [95] = "Thunderstorm", [96] = "Thunderstorm w/ Hail", [99] = "Heavy Hail",
        }

        local condition = weatherCodes[current.weather_code] or "Unknown"
        local is_night = current.is_day == 0

        -- Icon mapping
        local iconCode = is_night and "01n" or "01d"
        if current.weather_code >= 2 and current.weather_code <= 3 then
            iconCode = is_night and "02n" or "02d"
        elseif current.weather_code >= 45 and current.weather_code <= 48 then
            iconCode = "50d"
        elseif current.weather_code >= 51 and current.weather_code <= 67 then
            iconCode = is_night and "09n" or "09d"
        elseif current.weather_code >= 71 and current.weather_code <= 77 then
            iconCode = is_night and "13n" or "13d"
        elseif current.weather_code >= 80 and current.weather_code <= 82 then
            iconCode = is_night and "10n" or "10d"
        elseif current.weather_code >= 95 then
            iconCode = is_night and "11n" or "11d"
        end

        -- Store data for this location
        local idx = loc.city == "Bangkok" and "0" or "1"
        noctalia.state.set("weather.city_" .. idx, loc.city)
        noctalia.state.set("weather.country_" .. idx, loc.country)
        noctalia.state.set("weather.temp_" .. idx, current.temperature_2m)
        noctalia.state.set("weather.humidity_" .. idx, current.relative_humidity_2m)
        noctalia.state.set("weather.feels_like_" .. idx, current.apparent_temperature)
        noctalia.state.set("weather.wind_" .. idx, current.wind_speed_10m)
        noctalia.state.set("weather.condition_" .. idx, condition)
        noctalia.state.set("weather.icon_" .. idx, iconCode)
        noctalia.state.set("weather.is_night_" .. idx, is_night)
        noctalia.state.set("weather.status", "ok")
        noctalia.state.set("weather.tick", os.time())
    end)
end

local function fetchAll()
    for _, loc in ipairs(LOCATIONS) do
        fetchWeatherForLocation(loc)
    end
end

function update()
    noctalia.setUpdateInterval(UPDATE_INTERVAL)
    fetchAll()
end

-- Initial fetch
fetchAll()

function refresh()
    fetchAll()
end
