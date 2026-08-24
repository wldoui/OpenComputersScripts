-- ================================================================
-- OPEN SPACE CONTROL
-- GitHub Bootstrap Installer
--
-- Minecraft 1.12.2
-- OpenComputers 1.8.9a
--
-- Repository:
-- https://github.com/wldoui/OpenComputersScripts
--
-- Source:
-- Space/oc_space_control
--
-- Installs:
--   /boot.lua
--   /api_inspector.lua
--   /apps/*
--   /data/*
--   /drivers/*
--   /lib/*
-- ================================================================

local component = require("component")
local computer = require("computer")
local term = require("term")
local filesystem = require("filesystem")

local internet = nil
local serialization = nil

local API_BASE =
    "https://api.github.com/repos/wldoui/OpenComputersScripts/contents/Space/oc_space_control"

local RAW_BASE =
    "https://raw.githubusercontent.com/wldoui/OpenComputersScripts/main/Space/oc_space_control"

local VERSION_FILE = "/.open_space_control"

local installedFiles = 0
local failedFiles = 0

-- ================================================================
-- SERIALIZATION
-- ================================================================

do
    local ok, result = pcall(require, "serialization")

    if ok then
        serialization = result
    end
end

-- ================================================================
-- UI
-- ================================================================

local function clear()
    pcall(term.clear)
    pcall(term.setCursor, 1, 1)
end

local function separator()
    print("------------------------------------------------------------")
end

local function ok(text)
    print("[OK] " .. text)
end

local function fail(text)
    print("[ERROR] " .. text)
end

local function warn(text)
    print("[WARN] " .. text)
end

local function title()
    clear()

    print("============================================================")
    print("       OPEN SPACE CONTROL INSTALLER")
    print("============================================================")
    print("")
    print("Repository:")
    print("wldoui/OpenComputersScripts")
    print("")
    print("Path:")
    print("Space/oc_space_control")
    print("")
end

-- ================================================================
-- FILESYSTEM
-- ================================================================

local function filesystemWritable()
    -- OpenComputers/OpenOS versions differ slightly in the
    -- filesystem API. Instead of trusting isReadOnly(), actually
    -- test whether we can create and delete a file.

    local testPath = "/.osc_write_test"

    -- If a stale test file exists, try removing it first.
    if filesystem.exists(testPath) then
        pcall(filesystem.remove, testPath)
    end

    local handle, err = io.open(testPath, "w")

    if not handle then
        return false, tostring(err or "cannot create test file")
    end

    local writeOK, writeError = pcall(function()
        handle:write("OPEN SPACE CONTROL WRITE TEST")
    end)

    handle:close()

    if not writeOK then
        pcall(filesystem.remove, testPath)
        return false, tostring(writeError)
    end

    local exists = filesystem.exists(testPath)

    pcall(filesystem.remove, testPath)

    if not exists then
        return false, "file was not created"
    end

    return true
end

local function ensureDirectory(path)
    if filesystem.exists(path) then
        if filesystem.isDirectory(path) then
            return true
        end

        return false,
            "Path exists but is not a directory: " .. path
    end

    local okMake, result =
        pcall(filesystem.makeDirectory, path)

    if not okMake then
        return false, tostring(result)
    end

    if not filesystem.exists(path) then
        return false, "directory was not created"
    end

    return true
end

local function writeFile(path, data)
    local directory = filesystem.path(path)

    if directory and directory ~= "" then
        local okDir, dirError =
            ensureDirectory(directory)

        if not okDir then
            return false, dirError
        end
    end

    local handle, err = io.open(path, "w")

    if not handle then
        return false, tostring(err)
    end

    local okWrite, writeError =
        pcall(function()
            handle:write(data)
        end)

    handle:close()

    if not okWrite then
        return false, tostring(writeError)
    end

    return true
end

-- ================================================================
-- INTERNET CARD
-- ================================================================

local function findInternet()
    local address

    for addr in component.list("internet", true) do
        address = addr
        break
    end

    if not address then
        return false
    end

    local success, proxy =
        pcall(component.proxy, address)

    if not success or not proxy then
        return false
    end

    internet = proxy

    return true
end

-- ================================================================
-- HTTP
-- ================================================================

local function httpGet(url)

    if not internet then
        return nil, "Internet Card is not available"
    end

    local okRequest, handle =
        pcall(internet.request, url)

    if not okRequest then
        return nil, tostring(handle)
    end

    if not handle then
        return nil, "internet.request returned nil"
    end

    local chunks = {}

    while true do

        local okRead, data =
            pcall(handle.read, 4096)

        if not okRead then
            pcall(handle.close)
            return nil, tostring(data)
        end

        if data == nil then
            break
        end

        chunks[#chunks + 1] = data
    end

    pcall(handle.close)

    return table.concat(chunks)
end

-- ================================================================
-- JSON
-- ================================================================

local function decodeJSON(data)
    if not json then
        return nil, "json library unavailable"
    end
    
    local okDecode, result = pcall(json.decode, data)
    
    if not okDecode then
        return nil, tostring(result)
    end
    
    return result
end

-- ================================================================
-- GITHUB DIRECTORY
-- ================================================================

local function githubDirectory(path)

    local url = API_BASE

    if path and path ~= "" then
        url = url .. "/" .. path
    end

    local data, err = httpGet(url)

    if not data then
        return nil, err
    end

    local result, decodeError =
        decodeJSON(data)

    if not result then
        return nil, decodeError
    end

    return result
end

-- ================================================================
-- DOWNLOAD FILE
-- ================================================================

local function downloadFile(relativePath)

    print("")
    print("Downloading:")
    print("  " .. relativePath)

    local url =
        RAW_BASE .. "/" .. relativePath

    local data, err =
        httpGet(url)

    if not data then
        fail(relativePath)
        print("  " .. tostring(err))

        failedFiles =
            failedFiles + 1

        return false
    end

    local destination =
        "/" .. relativePath

    local success, writeError =
        writeFile(destination, data)

    if not success then
        fail(relativePath)
        print("  " .. tostring(writeError))

        failedFiles =
            failedFiles + 1

        return false
    end

    ok(relativePath)

    installedFiles =
        installedFiles + 1

    return true
end

-- ================================================================
-- RECURSIVE INSTALL
-- ================================================================

local function installDirectory(relativePath)

    local entries, err =
        githubDirectory(relativePath)

    if not entries then
        fail(
            "Cannot access GitHub directory: " ..
            tostring(relativePath)
        )

        print("Reason: " .. tostring(err))

        return false
    end

    if type(entries) ~= "table" then
        fail(
            "GitHub returned unexpected data"
        )

        return false
    end

    for _, entry in ipairs(entries) do

        if entry.type == "dir" then

            local childPath

            if relativePath == "" then
                childPath = entry.name
            else
                childPath =
                    relativePath .. "/" .. entry.name
            end

            local localPath =
                "/" .. childPath

            local okDir, dirError =
                ensureDirectory(localPath)

            if not okDir then

                fail(
                    "Cannot create " ..
                    localPath
                )

                print(
                    "  " ..
                    tostring(dirError)
                )

                return false
            end

            print("")
            print("[DIR] " .. localPath)

            local recursiveOK =
                installDirectory(childPath)

            if not recursiveOK then
                return false
            end

        elseif entry.type == "file" then

            local childPath

            if relativePath == "" then
                childPath = entry.name
            else
                childPath =
                    relativePath .. "/" .. entry.name
            end

            downloadFile(childPath)
        end
    end

    return true
end

-- ================================================================
-- VERSION
-- ================================================================

local function saveVersion()

    local version =
        "OPEN SPACE CONTROL\n" ..
        "Repository: wldoui/OpenComputersScripts\n" ..
        "Path: Space/oc_space_control\n" ..
        "Branch: main\n" ..
        "Installed: " ..
        os.date("%Y-%m-%d %H:%M:%S") ..
        "\n"

    writeFile(
        VERSION_FILE,
        version
    )
end

-- ================================================================
-- VERIFY
-- ================================================================

local function verify()

    separator()

    print("VERIFYING INSTALLATION")

    separator()

    print("")

    local files = {
        "/boot.lua",
        "/api_inspector.lua"
    }

    local directories = {
        "/apps",
        "/data",
        "/drivers",
        "/lib"
    }

    local valid = true

    for _, path in ipairs(files) do

        if filesystem.exists(path) then
            ok(path)
        else
            fail(path .. " missing")
            valid = false
        end
    end

    for _, path in ipairs(directories) do

        if filesystem.exists(path)
            and filesystem.isDirectory(path) then

            ok(path)

        else

            fail(path .. " missing")

            valid = false
        end
    end

    return valid
end

-- ================================================================
-- BOOT
-- ================================================================

local function startSystem()

    print("")
    print("Starting OPEN SPACE CONTROL...")
    print("")

    if not filesystem.exists("/boot.lua") then
        fail("/boot.lua does not exist")
        return
    end

    local okBoot, bootError =
        pcall(dofile, "/boot.lua")

    if not okBoot then
        print("")
        fail("boot.lua crashed")
        print("")
        print(tostring(bootError))
    end
end

-- ================================================================
-- MAIN
-- ================================================================

local function main()

    title()

    -- ------------------------------------------------------------
    -- FILESYSTEM
    -- ------------------------------------------------------------

    print("Checking filesystem...")

    local writable, writeError =
        filesystemWritable()

    if not writable then

        fail("Filesystem is not writable")

        print("")
        print(
            "Reason: " ..
            tostring(writeError)
        )

        print("")
        print(
            "Install OpenOS on a writable filesystem."
        )

        return
    end

    ok("Filesystem is writable")

    print("")

    -- ------------------------------------------------------------
    -- INTERNET
    -- ------------------------------------------------------------

    print("Checking Internet Card...")

    if not findInternet() then

        fail("Internet Card not found")

        print("")
        print(
            "Install an Internet Card into this computer."
        )

        return
    end

    ok("Internet Card detected")

    print("")

    -- ------------------------------------------------------------
    -- GITHUB
    -- ------------------------------------------------------------

    print("Testing GitHub connection...")

    local data, err =
        httpGet(API_BASE)

    if not data then

        fail("GitHub connection failed")

        print("")
        print(tostring(err))

        return
    end

    ok("GitHub reachable")

    local decoded, decodeError =
        decodeJSON(data)

    if not decoded then

        fail(
            "GitHub API response invalid"
        )

        print("")
        print(tostring(decodeError))

        return
    end

    ok("GitHub API response valid")

    print("")

    -- ------------------------------------------------------------
    -- DIRECTORIES
    -- ------------------------------------------------------------

    print("Preparing directories...")
    print("")

    local directories = {
        "/apps",
        "/data",
        "/drivers",
        "/lib"
    }

    for _, path in ipairs(directories) do

        local success, err =
            ensureDirectory(path)

        if not success then

            fail(path)

            print(
                "  " ..
                tostring(err)
            )

            return
        end

        ok(path)
    end

    print("")

    -- ------------------------------------------------------------
    -- INSTALL
    -- ------------------------------------------------------------

    separator()

    print("DOWNLOADING OPEN SPACE CONTROL")

    separator()

    print("")

    print(
        "Source:"
    )

    print(
        API_BASE
    )

    print("")

    local installOK =
        installDirectory("")

    if not installOK then

        print("")
        fail(
            "Installation encountered an error."
        )

        return
    end

    -- ------------------------------------------------------------
    -- VERSION
    -- ------------------------------------------------------------

    saveVersion()

    -- ------------------------------------------------------------
    -- VERIFY
    -- ------------------------------------------------------------

    local verified =
        verify()

    print("")

    separator()

    print("INSTALLATION RESULT")

    separator()

    print("")

    print(
        "Files installed: " ..
        tostring(installedFiles)
    )

    print(
        "Files failed:    " ..
        tostring(failedFiles)
    )

    print("")

    if not verified or failedFiles > 0 then

        fail(
            "Installation is incomplete."
        )

        print("")
        print(
            "Do not start Open Space Control yet."
        )

        return
    end

    print(
        "============================================================"
    )

    print(
        "       INSTALLATION COMPLETE"
    )

    print(
        "============================================================"
    )

    print("")

    print(
        "Installed:"
    )

    print(
        "  /boot.lua"
    )

    print(
        "  /api_inspector.lua"
    )

    print(
        "  /apps/"
    )

    print(
        "  /data/"
    )

    print(
        "  /drivers/"
    )

    print(
        "  /lib/"
    )

    print("")

    print(
        "Run:"
    )

    print(
        "  /boot.lua"
    )

    print("")

    term.write(
        "Start OPEN SPACE CONTROL now? [Y/n] "
    )

    local answer =
        term.read()

    if answer then
        answer =
            answer:gsub("%s+", ""):lower()
    else
        answer = ""
    end

    if answer == ""
        or answer == "y"
        or answer == "yes" then

        startSystem()

    else

        print("")
        print(
            "Installation finished."
        )

        print(
            "Run /boot.lua when ready."
        )
    end
end

main()