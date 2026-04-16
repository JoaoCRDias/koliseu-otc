-- this is the first file executed when the application starts
-- we have to load the first modules form here

local function getConfigValue(functionName, defaultValue)
    if g_configs and type(g_configs[functionName]) == "function" then
        local ok, value = pcall(g_configs[functionName])
        if ok and value ~= nil and value ~= "" then
            return value
        end
    end
    return defaultValue
end

-- updater/services loaded from config.ini via C++
Services = {
    updater = getConfigValue("getServiceUpdater", ""),
    updaterConfig = {
        remoteConfigUrl = getConfigValue("getServiceUpdaterRemoteConfigUrl", ""),
        zipUrl = getConfigValue("getServiceUpdaterZipUrl", ""),
        localConfigFile = getConfigValue("getServiceUpdaterLocalConfigFile", "/otc_config.json")
    },
    status = getConfigValue("getServiceStatus", ""),
    websites = getConfigValue("getServiceWebsites", ""),
    createAccount = getConfigValue("getServiceCreateAccount", ""),
    logUpload = getConfigValue("getServiceLogUpload", ""),
    polopag = getConfigValue("getServicePolopag", ""),
    polopagConfig = getConfigValue("getServicePolopagConfig", ""),
    getCoinsUrl = getConfigValue("getGameStoreGetCoins", ""),
    polopagOffers = {}
}

-- GameStoreLinks loaded from config.ini via C++
GameStoreLinks = {
    getCoins = getConfigValue("getGameStoreGetCoins", Services.getCoinsUrl or ""),
    images = getConfigValue("getGameStoreImages", "")
}

-- TibiaHintsUrl loaded from config.ini via C++
TibiaHintsUrl = getConfigValue("getTibiaHintsUrl", "")

-- Helper links loaded from config.ini via C++
Helpers = {
    Wiki = getConfigValue("getHelperWiki", ""),
    Info = getConfigValue("getHelperInfo", "")
}

--- Enables or disables the entire server configuration block.
-- Set to `false` to disable all configuration below.
local ENABLE_SERVERS = true

---
-- @module Servers_init
-- Configuration table for all servers used by the system.
--
-- This entire block is conditionally enabled based on ENABLE_SERVERS.
-- When ENABLE_SERVERS == false, everything is ignored/disabled.
--

---
-- Server configuration system for multi-server or multi-world clients.
--
-- This structure allows a single client build to connect to multiple servers
-- without requiring duplicate client folders.
--
-- A server that hosts several worlds, or that provides a separate test environment,
-- can simply define additional entries inside this configuration table.
--
-- Instead of maintaining multiple client installations (one per world/server),
-- the client can switch between servers by selecting the desired configuration entry.
-- This simplifies testing, avoids redundant directories, and centralizes connection settings.
--
-- The ENABLE_SERVERS flag allows the entire configuration block to be enabled or disabled
-- without deleting or commenting out individual entries.
--

Servers_init = {}

if ENABLE_SERVERS then

    ---
    -- List of servers and their configuration parameters.
    -- Each entry defines port, protocol, and authentication options.
    -- @table Servers_init
    --
    Servers_init = {

        -- Local login server
        ---
        -- Configuration for local login server.
        -- @class table
        -- @name local_login
        -- @field port Port used for HTTP connection
        -- @field protocol Protocol identifier used by the application
        -- @field httpLogin Enables HTTP-based login on the server
        -- @field useAuthenticator Enables additional authentication layer
        --
        ["http://127.0.0.1/login.php"] = {
            port = 80,
            protocol = 1523,
            httpLogin = true,
            useAuthenticator = false
        },

        -- External server
        ---
        -- Configuration for external server ip.net.
        -- @class table
        -- @name ip_net
        -- @field port TCP port used for connection
        -- @field protocol Protocol identifier used by the server
        -- @field httpLogin Indicates if the server allows HTTP login
        --
        ["http://127.0.0.1/login.php"] = {
            port = 80,
            protocol = 1523,
            httpLogin = true,
            useAuthenticator = false
        }
    }
end

g_app.setName("OTClient - Redemption");
g_app.setCompactName("otclient");
g_app.setOrganizationName("otcr");

g_app.hasUpdater = function()
    return (Services.updater and Services.updater ~= "" and g_modules.getModule("updater"))
end



FoodIds = {
    3577, 3578, 3579, 3581, 3582, 3583, 3585, 3586, 3587,
    3588, 3589, 3592, 3595, 3597, 3600, 3601, 3602, 3606,
    3607, 3723, 3724, 3725, 3728, 3731, 3732, 8011, 8014,
    8016, 8017, 12310, 14085, 17457, 17820, 17821, 21143,
    21144, 21146, 23535, 23545, 62069
}

InfiniteFoodIds = {
    61615, 61672, 61930, 62184, 62267, 62268, 63235, 63314,
    63723, 62069
}

ExerciseDummies = {
    28558, 28559, 28560, 28561, 28562, 28563, 28564, 28565,
	62021, 62022, 62023, 62024, 62071, 62072, 62085, 62086,
	62131, 62132, 62133, 62134, 62148, 62149, 62150, 62151,
	62152, 62153, 62922, 62923, 62924, 62925, 62926, 62927,
	63065, 63066, 63072, 63073
}

ExerciseIds = {
	28552, 28553, 28554, 28555, 28556, 28557, 35279, 35280,
	35281, 35282, 35283, 35284, 35285, 35286, 35287, 35288,
	35289, 35290, 44065, 44066, 44067, 50293, 50294, 50295,
	62641, 62642, 62643, 62644, 62645, 62646, 62647, 63224
}

CustomPotionIds = {
    { id = 63319, name = "Enhanced Supreme Health Potion",  type = "health" },
    { id = 63320, name = "Enhanced Ultimate Mana Potion",   type = "mana" },
    { id = 63318, name = "Enhanced Great Mana Potion",   type = "mana" },
    { id = 63321, name = "Enhanced Ultimate Spirit Potion", type = "health" }
}

CustomQuiverItemIds = {
      [63323] = true, -- enhanced spectral bolt.
      [63322] = true, -- enhanced diamond arrow.
}

-- Custom Rune IDs - Bypass Spells.getRuneSpellByItem validation
-- Add custom runes here to use them in the magic shooter/helper
-- Format: [itemId] = { group = 1, name = "Rune Name", exhaustion = 2000, area = "AREA_CIRCLE1X1"/"AREA_CIRCLE3X3" or false }
-- group: 1 = attack, 2 = healing, 3 = support
-- area: true for area runes, false/nil for single target
CustomRuneIds = {
     [63298] = { group = 1, name = "enhanced explosion rune", exhaustion = 2000, area = "AREA_CIRCLE1X1" },
     [63314] = { group = 2, name = "enhanced ultimate healing rune", exhaustion = 2000, area = false },
     [63313] = { group = 1, name = "enhanced thunderstorm rune", exhaustion = 2000, area = "AREA_CIRCLE3X3" },
     [63312] = { group = 1, name = "enhanced sudden death rune", exhaustion = 2000, area = false },
     [63311] = { group = 1, name = "enhanced stone shower rune", exhaustion = 2000, area = "AREA_CIRCLE3X3" },
     [63310] = { group = 1, name = "enhanced great fireball rune", exhaustion = 2000, area = "AREA_CIRCLE3X3" },
     [63309] = { group = 1, name = "enhanced avalanche rune", exhaustion = 2000, area = "AREA_CIRCLE3X3" }
}

local script = '/' .. g_app.getCompactName() .. 'rc.lua'

if g_resources.fileExists(script) then
    dofile(script)
end


if g_client and g_client.setEffectAlphaIgnoreIds then
    g_client.setEffectAlphaIgnoreIds({ 56, 173, 230, 231, 232, 244, 533 })
end

-- setup logger
g_logger.setLogFile(g_resources.getWorkDir() .. g_app.getCompactName() .. '.log')
g_logger.info(os.date('== application started at %b %d %Y %X'))
g_logger.info("== operating system: " .. g_platform.getOSName())

-- print first terminal message
g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' ..
    g_app.getBuildCommit() .. ') built on ' .. g_app.getBuildDate() .. ' for arch ' ..
    g_app.getBuildArch())

-- setup lua debugger
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    require("lldebugger").start()
    g_logger.debug("Started LUA debugger.")
else
    g_logger.debug("LUA debugger not started (not launched with VSCode local-lua).")
end

-- add data directory to the search path
if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'data', true) then
    g_logger.fatal('Unable to add data directory to the search path.')
end

-- add modules directory to the search path
if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'modules', true) then
    g_logger.fatal('Unable to add modules directory to the search path.')
end

g_html.addGlobalStyle('/data/styles/html.css')
g_html.addGlobalStyle('/data/styles/custom.css')

-- try to add mods path too
g_resources.addSearchPath(g_resources.getWorkDir() .. 'mods', true)

-- setup directory for saving configurations
g_resources.setupUserWriteDir(('%s/'):format(g_app.getCompactName()))

-- search all packages
g_resources.searchAndAddPackages('/', '.otpkg', true)

-- load settings
g_configs.loadSettings('/config.otml')

g_modules.discoverModules()

-- libraries modules 0-99
g_modules.autoLoadModules(99)
g_modules.ensureModuleLoaded('corelib')
g_modules.ensureModuleLoaded('gamelib')
g_modules.ensureModuleLoaded('modulelib')
g_modules.ensureModuleLoaded("startup")

g_modules.autoLoadModules(999)
g_modules.ensureModuleLoaded('game_shaders') -- pre load

local function loadModules()
    -- client modules 100-499
    g_modules.autoLoadModules(499)
    g_modules.ensureModuleLoaded('client')

    -- game modules 500-999
    g_modules.autoLoadModules(999)
    g_modules.ensureModuleLoaded('game_interface')


    -- mods 1000-9999
    g_modules.autoLoadModules(9999)
    g_modules.ensureModuleLoaded('client_mods')

    local script = '/' .. g_app.getCompactName() .. 'rc.lua'

    if g_resources.fileExists(script) then
        dofile(script)
    end

    -- uncomment the line below so that modules are reloaded when modified. (Note: Use only mod dev)
     g_modules.enableAutoReload()
end

-- run updater, must use data.zip
if g_app.hasUpdater() then
    g_modules.ensureModuleLoaded("updater")
    return Updater.init(loadModules)
end

loadModules()
