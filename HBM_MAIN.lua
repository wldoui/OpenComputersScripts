local component = require("component")
local computer = require("computer")
local event = require("event")

local gpu = component.gpu

local WIDTH = 160
local HEIGHT = 50

gpu.setResolution(WIDTH, HEIGHT)

local batteries = {}
local selected = 1
local running = true

local scroll = 0
local lastScan = 0
local lastDraw = 0

local MODE_INPUT = 0
local MODE_BUFFER = 1
local MODE_OUTPUT = 2

local PRIORITY_LOW = 0
local PRIORITY_NORMAL = 1
local PRIORITY_HIGH = 2


------------------------------------------------------------
-- BASIC DRAWING
------------------------------------------------------------

local function clear()
    gpu.fill(1, 1, WIDTH, HEIGHT, " ")
end

local function text(x, y, value)
    gpu.set(x, y, tostring(value))
end

local function line(y, char)
    gpu.fill(1, y, WIDTH, 1, char or "-")
end

local function center(y, value)
    value = tostring(value)

    local x = math.floor((WIDTH - #value) / 2) + 1

    if x < 1 then
        x = 1
    end

    gpu.set(x, y, value)
end


------------------------------------------------------------
-- FORMATTING
------------------------------------------------------------

local function formatNumber(value)
    value = math.floor(value or 0)

    local negative = value < 0

    if negative then
        value = -value
    end

    local s = tostring(value)

    while true do
        local result, count =
            s:gsub("^(%d+)(%d%d%d)", "%1 %2")

        s = result

        if count == 0 then
            break
        end
    end

    if negative then
        s = "-" .. s
    end

    return s
end


local function formatSigned(value)
    value = math.floor(value or 0)

    if value > 0 then
        return "+" .. formatNumber(value)
    end

    return formatNumber(value)
end


local function percent(current, maximum)
    if not maximum or maximum <= 0 then
        return 0
    end

    return current / maximum * 100
end


------------------------------------------------------------
-- MODE / PRIORITY NAMES
------------------------------------------------------------

local function modeName(mode)
    if mode == MODE_INPUT then
        return "INPUT"
    elseif mode == MODE_BUFFER then
        return "BUFFER"
    elseif mode == MODE_OUTPUT then
        return "OUTPUT"
    end

    return "UNKNOWN"
end


local function priorityName(priority)
    if priority == PRIORITY_LOW then
        return "LOW"
    elseif priority == PRIORITY_NORMAL then
        return "NORMAL"
    elseif priority == PRIORITY_HIGH then
        return "HIGH"
    end

    return "UNKNOWN"
end


------------------------------------------------------------
-- SAFE API CALL
------------------------------------------------------------

local function call(proxy, method, ...)
    local ok, a, b, c, d, e =
        pcall(proxy[method], proxy, ...)

    if not ok then
        return nil
    end

    return a, b, c, d, e
end


------------------------------------------------------------
-- READ BATTERY
------------------------------------------------------------

local function readBattery(address)
    local proxy = component.proxy(address)

    if not proxy then
        return nil
    end

    local current, maximum, delta =
        call(proxy, "getEnergyInfo")

    local modeLow, modeHigh, priority =
        call(proxy, "getModeInfo")

    local packName, chargeRate, dischargeRate =
        call(proxy, "getPackInfo")

    return {
        address = address,
        proxy = proxy,

        current = current or 0,
        maximum = maximum or 0,
        delta = delta or 0,

        modeLow = modeLow or 0,
        modeHigh = modeHigh or 0,

        priority = priority or 0,

        packName = packName or "UNKNOWN",

        chargeRate = chargeRate or 0,
        dischargeRate = dischargeRate or 0
    }
end


------------------------------------------------------------
-- SCAN ALL HBM BATTERIES
------------------------------------------------------------

local function scan()
    local oldSelectionAddress = nil

    if batteries[selected] then
        oldSelectionAddress =
            batteries[selected].address
    end

    local result = {}

    for address in component.list("ntm_energy_storage") do

        local battery = readBattery(address)

        if battery then
            table.insert(result, battery)
        end
    end

    batteries = result

    selected = 1

    if oldSelectionAddress then

        for i, battery in ipairs(batteries) do

            if battery.address == oldSelectionAddress then
                selected = i
                break
            end

        end
    end

    if selected > #batteries then
        selected = #batteries
    end

    if selected < 1 then
        selected = 1
    end

    lastScan = computer.uptime()
end


------------------------------------------------------------
-- TOTAL ENERGY
------------------------------------------------------------

local function getTotals()
    local current = 0
    local maximum = 0
    local delta = 0

    for _, battery in ipairs(batteries) do

        current =
            current + battery.current

        maximum =
            maximum + battery.maximum

        delta =
            delta + battery.delta

    end

    return current, maximum, delta
end


------------------------------------------------------------
-- HEADER
------------------------------------------------------------

local function drawHeader()

    center(
        1,
        "HBM CE ENERGY GRID CONTROL"
    )

    line(2, "=")

    text(
        3,
        3,
        "OPENCOMPUTERS"
    )

    text(
        130,
        3,
        "160 x 50"
    )
end


------------------------------------------------------------
-- TOTAL NETWORK
------------------------------------------------------------

local function drawTotal()

    local current, maximum, delta =
        getTotals()

    local p =
        percent(current, maximum)

    text(
        3,
        5,
        "TOTAL STORAGE"
    )

    text(
        3,
        6,
        formatNumber(current)
        .. " / "
        .. formatNumber(maximum)
        .. " HE"
    )

    text(
        50,
        6,
        string.format(
            "%.2f%%",
            p
        )
    )

    text(
        75,
        6,
        "NET:"
    )

    text(
        80,
        6,
        formatSigned(delta)
        .. " HE/s"
    )

    text(
        110,
        6,
        "BATTERIES:"
    )

    text(
        122,
        6,
        #batteries
    )

    line(8)
end


------------------------------------------------------------
-- BATTERY TABLE
------------------------------------------------------------

local function drawBatteryTable()

    text(1, 9, "ID")
    text(7, 9, "ADDRESS")
    text(43, 9, "ENERGY")
    text(65, 9, "MAX")
    text(84, 9, "CHARGE")
    text(101, 9, "FLOW")
    text(117, 9, "MODE")
    text(130, 9, "PRIORITY")
    text(145, 9, "%")

    line(10)

    local first = scroll + 1
    local last = math.min(
        #batteries,
        first + 24
    )

    local y = 11

    for i = first, last do

        local battery = batteries[i]

        local marker = " "

        if i == selected then
            marker = ">"
        end

        local p =
            percent(
                battery.current,
                battery.maximum
            )

        text(
            1,
            y,
            marker .. string.format("%02d", i)
        )

        text(
            7,
            y,
            string.sub(
                battery.address,
                1,
                34
            )
        )

        text(
            43,
            y,
            formatNumber(
                battery.current
            )
        )

        text(
            65,
            y,
            formatNumber(
                battery.maximum
            )
        )

        text(
            84,
            y,
            formatNumber(
                battery.chargeRate
            )
        )

        text(
            101,
            y,
            formatSigned(
                battery.delta
            )
        )

        text(
            117,
            y,
            modeName(
                battery.modeLow
            )
        )

        text(
            130,
            y,
            priorityName(
                battery.priority
            )
        )

        text(
            145,
            y,
            string.format(
                "%6.1f%%",
                p
            )
        )

        y = y + 1
    end

    line(36)
end


------------------------------------------------------------
-- SELECTED BATTERY
------------------------------------------------------------

local function drawSelected()

    if #batteries == 0 then

        text(
            3,
            38,
            "NO HBM ENERGY STORAGE COMPONENTS FOUND."
        )

        text(
            3,
            40,
            "Connect HBM energy storage blocks to the OpenComputers network."
        )

        return
    end

    local battery =
        batteries[selected]

    text(
        3,
        38,
        "SELECTED BATTERY #" .. selected
    )

    text(
        3,
        39,
        "Address: " .. battery.address
    )

    text(
        3,
        41,
        "Battery Pack:"
    )

    text(
        17,
        41,
        battery.packName
    )

    text(
        3,
        42,
        "Energy:"
    )

    text(
        12,
        42,
        formatNumber(battery.current)
        .. " / "
        .. formatNumber(battery.maximum)
        .. " HE"
    )

    text(
        55,
        42,
        string.format(
            "%.2f%%",
            percent(
                battery.current,
                battery.maximum
            )
        )
    )

    text(
        75,
        42,
        "Flow:"
    )

    text(
        81,
        42,
        formatSigned(
            battery.delta
        )
        .. " HE/s"
    )

    text(
        3,
        43,
        "Charge:"
    )

    text(
        12,
        43,
        formatNumber(
            battery.chargeRate
        )
        .. " HE/t"
    )

    text(
        35,
        43,
        "Discharge:"
    )

    text(
        47,
        43,
        formatNumber(
            battery.dischargeRate
        )
        .. " HE/t"
    )

    text(
        75,
        43,
        "LOW:"
    )

    text(
        81,
        43,
        modeName(
            battery.modeLow
        )
    )

    text(
        100,
        43,
        "HIGH:"
    )

    text(
        107,
        43,
        modeName(
            battery.modeHigh
        )
    )

    text(
        3,
        44,
        "Priority:"
    )

    text(
        13,
        44,
        priorityName(
            battery.priority
        )
    )
end


------------------------------------------------------------
-- CONTROLS
------------------------------------------------------------

local function drawControls()

    line(46)

    text(
        2,
        47,
        "[UP/DOWN] SELECT"
    )

    text(
        25,
        47,
        "[I] INPUT"
    )

    text(
        42,
        47,
        "[B] BUFFER"
    )

    text(
        61,
        47,
        "[O] OUTPUT"
    )

    text(
        81,
        47,
        "[P] PRIORITY"
    )

    text(
        103,
        47,
        "[R] RESCAN"
    )

    text(
        122,
        47,
        "[Q] EXIT"
    )

    text(
        2,
        49,
        "Mode:  INPUT = charge only | BUFFER = charge/discharge | OUTPUT = discharge only"
    )
end


------------------------------------------------------------
-- DRAW EVERYTHING
------------------------------------------------------------

local function draw()

    clear()

    drawHeader()

    drawTotal()

    drawBatteryTable()

    drawSelected()

    drawControls()
end


------------------------------------------------------------
-- SET MODE
------------------------------------------------------------

local function setMode(mode)

    if not batteries[selected] then
        return
    end

    local battery =
        batteries[selected]

    local proxy =
        battery.proxy

    local successLow =
        pcall(
            proxy.setModeLow,
            proxy,
            mode
        )

    local successHigh =
        pcall(
            proxy.setModeHigh,
            proxy,
            mode
        )

    if successLow and successHigh then

        battery.modeLow = mode
        battery.modeHigh = mode

    end
end


------------------------------------------------------------
-- PRIORITY
------------------------------------------------------------

local function nextPriority()

    if not batteries[selected] then
        return
    end

    local battery =
        batteries[selected]

    local newPriority =
        (battery.priority + 1) % 3

    local ok =
        pcall(
            battery.proxy.setPriority,
            battery.proxy,
            newPriority
        )

    if ok then
        battery.priority = newPriority
    end
end


------------------------------------------------------------
-- SELECTION
------------------------------------------------------------

local function selectBattery(index)

    if #batteries == 0 then
        return
    end

    if index < 1 then
        index = 1
    end

    if index > #batteries then
        index = #batteries
    end

    selected = index

    if selected <= scroll then
        scroll = selected - 1
    end

    if selected > scroll + 25 then
        scroll = selected - 25
    end
end


local function moveSelection(delta)

    selectBattery(
        selected + delta
    )
end


------------------------------------------------------------
-- KEYBOARD
------------------------------------------------------------

local function keyboardHandler(char, code)

    -- Q
    if char == string.byte("q")
        or char == string.byte("Q") then

        running = false

    -- R
    elseif char == string.byte("r")
        or char == string.byte("R") then

        scan()

    -- I
    elseif char == string.byte("i")
        or char == string.byte("I") then

        setMode(MODE_INPUT)

    -- B
    elseif char == string.byte("b")
        or char == string.byte("B") then

        setMode(MODE_BUFFER)

    -- O
    elseif char == string.byte("o")
        or char == string.byte("O") then

        setMode(MODE_OUTPUT)

    -- P
    elseif char == string.byte("p")
        or char == string.byte("P") then

        nextPriority()

    -- 1
    elseif char == string.byte("1") then

        setMode(MODE_INPUT)

    -- 2
    elseif char == string.byte("2") then

        setMode(MODE_BUFFER)

    -- 3
    elseif char == string.byte("3") then

        setMode(MODE_OUTPUT)

    -- UP ARROW
    elseif code == 200 then

        moveSelection(-1)

    -- DOWN ARROW
    elseif code == 208 then

        moveSelection(1)

    end
end


------------------------------------------------------------
-- INITIAL SCAN
------------------------------------------------------------

scan()

draw()


------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------

while running do

    local now =
        computer.uptime()

    if now - lastScan >= 2 then

        scan()

    end

    if now - lastDraw >= 0.5 then

        -- Refresh information
        for i, battery in ipairs(batteries) do

            local updated =
                readBattery(
                    battery.address
                )

            if updated then
                batteries[i] = updated
            end

        end

        draw()

        lastDraw = now
    end

    local eventName, _, char, code =
        event.pull(0.1)

    if eventName == "key_down" then

        keyboardHandler(
            char,
            code
        )

    end
end


------------------------------------------------------------
-- EXIT
------------------------------------------------------------

clear()

center(
    25,
    "HBM ENERGY CONTROL STOPPED"
)

os.sleep(1)

clear()