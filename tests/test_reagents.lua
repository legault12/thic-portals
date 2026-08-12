-- Standalone regression tests for reagent stock and low-stock warnings.
--
-- Every portal and teleport burns a rune, and nothing tracked them: running dry stopped the shop
-- dead with no warning. Counting is deliberately forgiving about how the item is identified,
-- because an item id that is wrong for this client would otherwise silently report zero forever.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_reagents.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false,
        reagentWarningThreshold = 20
    },
    Portals = {}
}

local bagById = {}
local bagByName = {}
local printed = {}

_G.time = function()
    return 100
end
_G.GetTime = function()
    return 100
end
_G.GetItemCount = function(identifier)
    if type(identifier) == "number" then
        return bagById[identifier]
    end
    return bagByName[identifier]
end

local realPrint = print
_G.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    printed[#printed + 1] = table.concat(parts, " ")
end

local Utils = dofile(addonDirectory .. "/Utils.lua")

local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        realPrint("  FAIL: " .. message)
    end
end

local function said(fragment)
    for _, line in ipairs(printed) do
        if line:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

local function stock(portalRunes, teleportRunes)
    bagById = {
        [17032] = portalRunes,
        [17031] = teleportRunes
    }
    bagByName = {}
    printed = {}
end

-- 1. Counting -------------------------------------------------------------------------------------

stock(45, 12)
check(Utils.getReagentCount("portal") == 45, "portal runes should be counted, got " .. Utils.getReagentCount("portal"))
check(Utils.getReagentCount("teleport") == 12, "teleport runes should be counted")
check(Utils.getReagentCount("nonsense") == 0, "an unknown reagent counts as none")

-- An item id that is wrong for this client must not silently report zero: the name still answers.
bagById = {}
bagByName = {
    ["Rune of Portals"] = 30
}
check(Utils.getReagentCount("portal") == 30, "a wrong id should fall back to the name, got " ..
    Utils.getReagentCount("portal"))

-- And the reverse, for a localised client where the English name will not match.
bagById = {
    [17032] = 30
}
bagByName = {}
check(Utils.getReagentCount("portal") == 30, "a name that does not match should fall back to the id")

-- Whichever answers higher wins, so a partial answer never hides a full one.
bagById = {
    [17032] = 5
}
bagByName = {
    ["Rune of Portals"] = 40
}
check(Utils.getReagentCount("portal") == 40, "the better answer should win")

-- Nothing at all is zero, not nil.
stock(nil, nil)
check(Utils.getReagentCount("portal") == 0, "an empty bag counts as zero")

-- 2. Which reagent a spell burns ---------------------------------------------------------------------

check(Utils.reagentForSpell("Portal: Ironforge") == "portal", "a portal burns portal runes")
check(Utils.reagentForSpell("Teleport: Ironforge") == "teleport", "a teleport burns teleport runes")
check(Utils.reagentForSpell("Fireball") == nil, "an ordinary spell burns neither")
check(Utils.reagentForSpell(nil) == nil, "no spell burns neither")
check(Utils.reagentForSpell("Portalish") == nil, "a name that merely starts similarly is not a portal")

-- 3. Warnings ------------------------------------------------------------------------------------------

-- Comfortable stock says nothing unless asked.
stock(100, 100)
Utils.checkReagentStock("portal")
check(#printed == 0, "plenty of runes should not warn")

-- Opening the shop states the position either way.
stock(100, 100)
Utils.checkReagentStock("portal", true)
check(said("Rune of Portals: 100"), "an explicit check should report the count")

-- At or below the threshold, it warns.
stock(20, 100)
Utils.checkReagentStock("portal")
check(said("Low on Rune of Portals: 20"), "the threshold itself should warn, got: " .. table.concat(printed, " | "))

-- Once per episode, not on every cast.
printed = {}
Utils.checkReagentStock("portal")
check(#printed == 0, "the low warning should not repeat while still low")

-- Recovering re-arms it.
stock(100, 100)
Utils.checkReagentStock("portal")
printed = {}
stock(15, 100)
Utils.checkReagentStock("portal")
check(said("Low on Rune of Portals"), "restocking then running low again should warn afresh")

-- Running out is its own level: already having been warned about being low must not silence the
-- moment the shop actually stops working.
stock(0, 100)
printed = {}
Utils.checkReagentStock("portal")
check(said("Out of Rune of Portals"), "an empty bag should say so, got: " .. table.concat(printed, " | "))
check(said("Low on") == false, "empty is not merely low")

-- ...and having said it once, it does not repeat either.
printed = {}
Utils.checkReagentStock("portal")
check(#printed == 0, "the empty warning should not repeat")

-- The threshold is configurable, and zero means only warn when actually out.
Config.Settings.reagentWarningThreshold = 0
stock(1, 100)
printed = {}
Utils.checkReagentStock("portal")
check(#printed == 0, "with a zero threshold, one rune is not low")

stock(0, 100)
printed = {}
Utils.checkReagentStock("portal")
check(said("Out of Rune of Portals"), "with a zero threshold, empty still warns")
Config.Settings.reagentWarningThreshold = 20

-- A missing setting falls back rather than erroring.
Config.Settings.reagentWarningThreshold = nil
check(Utils.reagentWarningThreshold() == 20, "the threshold should default when unset")
Config.Settings.reagentWarningThreshold = 20

-- The two reagents warn independently.
stock(100, 3)
printed = {}
Utils.checkAllReagentStock()
check(said("Low on Rune of Teleportation"), "teleport runes should warn on their own")
check(said("Low on Rune of Portals") == false, "a healthy portal stock should stay quiet")

-- ------------------------------------------------------------------------------------------------

_G.print = realPrint

if failures > 0 then
    error(string.format("reagents: %d check(s) failed", failures))
end

print("reagents: counting, id and name fallback, spell mapping and threshold warnings all passed")
