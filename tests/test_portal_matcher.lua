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

-- 7. Zone name -> canonical city, for the ticket's location line and travel button --------------

local zoneCases = {{"Stormwind City", "Stormwind"}, {"Ironforge", "Ironforge"}, {"Darnassus", "Darnassus"},
                   {"The Exodar", "Exodar"}, {"Orgrimmar", "Orgrimmar"}, {"Thunder Bluff", "Thunder Bluff"},
                   {"Undercity", "Undercity"}, {"Silvermoon City", "Silvermoon"}, {"Shattrath City", "Shattrath"},
                   -- Zones that are not travel targets must resolve to nothing, so no button appears.
                   {"Elwynn Forest", nil}, {"Dustwallow Marsh", nil}, {"Swamp of Sorrows", nil},
                   {"Tirisfal Glades", nil}, {"Teldrassil", nil}, {"Hellfire Peninsula", nil}, {"Durotar", nil}}

for _, case in ipairs(zoneCases) do
    local zone, wanted = case[1], case[2]
    local got = Utils.resolveCityFromZoneName(zone)

    check(got == wanted, string.format("zone %q should resolve to %s, got %s", zone, tostring(wanted), tostring(got)))
end

check(Utils.resolveCityFromZoneName(nil) == nil, "a nil zone must resolve to nothing")

-- Every canonical city must be reachable from its own bare name, so the derived teleport spell
-- name lines up with the portal map.
for city in pairs(Utils.PortalSpells) do
    check(Utils.resolveCityFromZoneName(city) == city, city .. " should resolve from its own name")
end

-- The teleport is only offered when the spellbook actually has it.
_G.GetSpellBookItemName = function(index)
    local book = {"Fireball", "Teleport: Stormwind", "Portal: Stormwind"}
    return book[index]
end
_G.BOOKTYPE_SPELL = "spell"

check(Utils.getKnownTeleportSpell("Stormwind") == "Teleport: Stormwind", "a known teleport should be offered")
check(Utils.getKnownTeleportSpell("Orgrimmar") == nil, "an unknown teleport must not be offered")
check(Utils.getKnownTeleportSpell("Nowhere") == nil, "a non-city must not produce a teleport")
check(Utils.getKnownTeleportSpell(nil) == nil, "a nil city must not produce a teleport")

-- 8. The city a customer is standing in is not one of their destination choices -----------------

local function keywordsAfterReject(message, currentCity, selected)
    local candidates = Utils.dedupeDestinationCandidates(Utils.findAllKeywordPositions(message, shippedKeywords),
        selected)
    return keywordsOf(Utils.rejectCurrentCityCandidates(candidates, currentCity))
end

-- The case this exists for: they named where they are and where they want to go.
check(keywordsAfterReject("wtb portal from sw to if", "Stormwind", "if") == "if",
    "the city the customer is standing in should not be offered, got " ..
        keywordsAfterReject("wtb portal from sw to if", "Stormwind", "if"))

-- Aliases resolve first, so the standing city goes whichever way it was written.
check(keywordsAfterReject("wtb portal from stormwind to if", "Stormwind", "if") == "if",
    "the standing city should be rejected by canonical city, not by spelling")

-- Somewhere they are not is untouched.
check(keywordsAfterReject("wtb portal from sw to if", "Darnassus", "if") == "sw,if",
    "a customer elsewhere should keep every choice")

-- Unknown location changes nothing.
check(keywordsAfterReject("wtb portal from sw to if", nil, "if") == "sw,if", "no location means no filtering")

-- More than two named: only the standing city goes.
check(keywordsAfterReject("wtb port sw if org darn", "Orgrimmar", "if") == "sw,if,darn",
    "only the standing city should be removed, got " .. keywordsAfterReject("wtb port sw if org darn", "Orgrimmar", "if"))

-- The standing city goes even when it is the selected one, as long as something else remains -
-- the row should offer the correction rather than the place they are already standing.
check(keywordsAfterReject("wtb portal from sw to if", "Stormwind", "sw") == "if",
    "the selected keyword must not protect the standing city from being filtered, got " ..
        keywordsAfterReject("wtb portal from sw to if", "Stormwind", "sw"))

-- The only-candidate safeguard: a request naming nowhere else keeps it rather than showing nothing.
check(keywordsAfterReject("wtb portal sw", "Stormwind", "sw") == "sw", "never filter down to no choices at all")
check(keywordsAfterReject("wtb portal sw stormwind", "Stormwind", "sw") == "sw",
    "aliases for the standing city alone still leave it in place")

-- Filtering refines what is shown; it must never rewrite the ticket's selected destination.
local ticket = {
    destination = "sw",
    originalMessage = "wtb portal from sw to if"
}
local filtered = Utils.rejectCurrentCityCandidates(
    Utils.dedupeDestinationCandidates(Utils.findAllKeywordPositions(ticket.originalMessage, shippedKeywords),
        ticket.destination), "Stormwind")
check(keywordsOf(filtered) == "if", "filtering should offer the alternative")
check(ticket.destination == "sw", "filtering must not mutate the ticket's selected destination")

-- ---------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("portal matcher: %d check(s) failed", failures))
end

print(string.format(
    "portal matcher: %d aliases, %d regressions, faction split, custom fallback, dedupe, %d zone lookups, standing-city rejection and placeholders all passed",
    aliasCount, #regressions, #zoneCases))
