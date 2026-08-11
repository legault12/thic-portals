-- Standalone regression tests for portal destination resolution and chip deduplication.
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_portal_matcher.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

-- The shipped DestinationKeywords list, plus two keywords a user might add themselves.
local shippedKeywords = {"darn", "darnassuss", "darnas", "darrna", "darnaas", "darnassus", "darnasuss", "darna",
                         "darnasus", "sw", "stormwind", "storm wind", "if", "ironforge", "iron forge", "exodar", "exo",
                         "theramore", "thera", "tmore", "org", "orgrimmar", "orgri", "orgim", "tb", "thunder bluff",
                         "thunderbluff", "thunder", "uc", "undercity", "under city", "silvermoon", "silver moon", "sm",
                         "silv", "stonard", "ston", "shattrath", "shatt", "shat", "shath"}

_G.Config = {
    Settings = {
        debugMode = false,
        DestinationKeywords = shippedKeywords
    },
    -- Used only by the heuristic fallback.
    Portals = {"Portal: Darnassus", "Portal: Stormwind", "Portal: Ironforge", "Portal: Exodar", "Portal: Theramore",
               "Portal: Orgrimmar", "Portal: Thunder Bluff", "Portal: Undercity", "Portal: Silvermoon",
               "Portal: Stonard", "Portal: Shattrath"}
}

_G.UnitFactionGroup = function()
    return "Alliance"
end

local Utils = dofile(addonDirectory .. "/Utils.lua")

local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        print("  FAIL: " .. message)
    end
end

-- 1. Every shipped alias resolves to the city it actually names ------------------------------

local expectedCity = {
    darn = "Darnassus",
    darnassuss = "Darnassus",
    darnas = "Darnassus",
    darrna = "Darnassus",
    darnaas = "Darnassus",
    darnassus = "Darnassus",
    darnasuss = "Darnassus",
    darna = "Darnassus",
    darnasus = "Darnassus",
    sw = "Stormwind",
    stormwind = "Stormwind",
    ["storm wind"] = "Stormwind",
    ["if"] = "Ironforge",
    ironforge = "Ironforge",
    ["iron forge"] = "Ironforge",
    exodar = "Exodar",
    exo = "Exodar",
    theramore = "Theramore",
    thera = "Theramore",
    tmore = "Theramore",
    org = "Orgrimmar",
    orgrimmar = "Orgrimmar",
    orgri = "Orgrimmar",
    orgim = "Orgrimmar",
    tb = "Thunder Bluff",
    ["thunder bluff"] = "Thunder Bluff",
    thunderbluff = "Thunder Bluff",
    thunder = "Thunder Bluff",
    uc = "Undercity",
    undercity = "Undercity",
    ["under city"] = "Undercity",
    silvermoon = "Silvermoon",
    ["silver moon"] = "Silvermoon",
    sm = "Silvermoon",
    silv = "Silvermoon",
    stonard = "Stonard",
    ston = "Stonard",
    shattrath = "Shattrath",
    shatt = "Shattrath",
    shat = "Shattrath",
    shath = "Shattrath"
}

local aliasCount = 0

for _, keyword in ipairs(shippedKeywords) do
    aliasCount = aliasCount + 1

    local portal = Utils.getMatchingPortal(keyword)
    local wanted = expectedCity[keyword]

    check(portal.matched, keyword .. " should resolve to a portal")
    check(portal.locationName == wanted,
        string.format("%q should resolve to %s, got %s", keyword, wanted, tostring(portal.locationName)))
    check(portal.canonical == wanted, string.format("%q should be flagged as explicitly mapped", keyword))
    check(portal.spellID ~= nil, keyword .. " should carry a spell id")
end

check(aliasCount == 41, "expected 41 shipped destination keywords, found " .. aliasCount)

-- 2. The four keywords the old letter-scoring matcher misrouted ------------------------------

local regressions = {{"org", "Orgrimmar", "Ironforge"}, {"orgri", "Orgrimmar", "Ironforge"},
                     {"sm", "Silvermoon", "Stormwind"}, {"ston", "Stonard", "Stormwind"}}

for _, case in ipairs(regressions) do
    local keyword, wanted, oldWrongAnswer = case[1], case[2], case[3]
    local portal = Utils.getMatchingPortal(keyword)

    check(portal.locationName == wanted,
        string.format("regression: %q must resolve to %s, not %s", keyword, wanted, tostring(portal.locationName)))
    check(portal.locationName ~= oldWrongAnswer,
        string.format("regression: %q must no longer resolve to %s", keyword, oldWrongAnswer))
end

-- 3. Faction-specific spell selection --------------------------------------------------------

check(Utils.getMatchingPortal("shatt").spellID == 33691, "Alliance Shattrath portal should be 33691")

_G.UnitFactionGroup = function()
    return "Horde"
end
check(Utils.getMatchingPortal("shatt").spellID == 35717, "Horde Shattrath portal should be 35717")
_G.UnitFactionGroup = function()
    return "Alliance"
end

-- 4. Custom keywords still resolve, via the isolated heuristic fallback ----------------------

check(Utils.resolveCanonicalDestination("bigcity") == nil, "an unmapped keyword must not resolve through the map")

local custom = Utils.getMatchingPortal("stormwynd") -- user-added misspelling, not in the shipped list
check(custom.matched, "a custom keyword should still resolve via the heuristic fallback")
check(custom.canonical == nil, "a heuristic result must not be flagged as explicitly mapped")

-- 5. Deduplication ---------------------------------------------------------------------------

local function keywordsOf(candidates)
    local out = {}
    for _, candidate in ipairs(candidates) do
        out[#out + 1] = candidate.keyword
    end
    return table.concat(out, ",")
end

local function candidatesFor(message, selected)
    return Utils.dedupeDestinationCandidates(Utils.findAllKeywordPositions(message, shippedKeywords), selected)
end

-- Aliases for one city collapse to the first one named.
check(keywordsOf(candidatesFor("port to if from sw, im in stormwind")) == "if,sw",
    "sw and stormwind are the same city and should collapse to one chip, got " ..
        keywordsOf(candidatesFor("port to if from sw, im in stormwind")))

-- Distinct cities are never merged - this is the pair the old matcher scored identically.
check(keywordsOf(candidatesFor("wtb port if or org")) == "if,org",
    "if and org are different cities and must stay separate, got " .. keywordsOf(candidatesFor("wtb port if or org")))

-- Four distinct cities survive untouched.
check(keywordsOf(candidatesFor("wtb port sw if org darn")) == "sw,if,org,darn", "four distinct cities must all survive")

-- An unmapped keyword is kept and never merged into anything.
local withCustom = {"sw", "stormwind", "bigcity", "othercity"}
local deduped = Utils.dedupeDestinationCandidates({{
    position = 1,
    keyword = "sw"
}, {
    position = 2,
    keyword = "stormwind"
}, {
    position = 3,
    keyword = "bigcity"
}, {
    position = 4,
    keyword = "othercity"
}})
check(keywordsOf(deduped) == "sw,bigcity,othercity",
    "unmapped keywords must be kept and never merged, got " .. keywordsOf(deduped))
check(#withCustom == 4, "sanity")

-- 6. The selected alias survives dedupe even when it is not the first alias named ---------------

-- "stormwind" is named before "sw", but "sw" is what parsing selected. Keeping the first alias
-- would drop "sw", leaving the selected destination unpinned and never shown in gold.
local notFirst = candidatesFor("port from stormwind to if, or sw", "sw")
check(keywordsOf(notFirst) == "sw,if",
    "the selected alias must survive dedupe even when named second, got " .. keywordsOf(notFirst))

local selectedStillPresent = false
for _, candidate in ipairs(notFirst) do
    if candidate.keyword == "sw" then
        selectedStillPresent = true
    end
end
check(selectedStillPresent, "selected destination must remain among the deduped candidates")

-- The group keeps its position in the message: Stormwind was named first, so it stays first.
check(notFirst[1] and notFirst[1].keyword == "sw", "the preserved alias should hold its group's place in the row")

-- Without a selection the first alias named still wins, as before.
check(keywordsOf(candidatesFor("port from stormwind to if, or sw")) == "stormwind,if",
    "with no selection the first alias named should still win")

-- A selected keyword that is not among the candidates changes nothing.
check(keywordsOf(candidatesFor("port from stormwind to if, or sw", "darn")) == "stormwind,if",
    "an absent selection must not alter deduplication")

-- ---------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("portal matcher: %d check(s) failed", failures))
end

print(string.format("portal matcher: %d aliases, %d regressions, faction split, custom fallback and dedupe all passed",
    aliasCount, #regressions))
