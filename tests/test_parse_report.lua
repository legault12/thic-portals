-- Standalone regression tests for the /Tp parse diagnostic.
--
-- The report is what a user will trust when the matcher does something surprising, so it has to
-- agree with the matcher rather than approximate it. These cases pin the fields the command prints.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_parse_report.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

local keywords = {"darn", "darnassus", "sw", "stormwind", "if", "ironforge", "org", "orgrimmar", "shatt", "uc"}

_G.Config = {
    Settings = {
        debugMode = false,
        DestinationKeywords = keywords,
        IntentKeywords = {"wtb", "lf", "need"},
        ServiceKeywords = {"portal", "port", "tp"},
        commonPhrases = {"wtb portal", "wtb port"},
        KeywordBanList = {},
        BanList = {},
        disableSmartMatching = false,
        requireDestination = false,
        soundEnabled = false
    },
    Portals = {"Portal: Darnassus", "Portal: Stormwind", "Portal: Ironforge", "Portal: Orgrimmar",
               "Portal: Undercity", "Portal: Shattrath"}
}

_G.UnitFactionGroup = function()
    return "Alliance"
end
_G.Events = {
    pendingInvites = {}
}

local Utils = dofile(addonDirectory .. "/Utils.lua")
local InviteTrade = dofile(addonDirectory .. "/InviteTrade.lua")

local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        print("  FAIL: " .. message)
    end
end

local function keywordsOf(candidates)
    local out = {}
    for _, candidate in ipairs(candidates) do
        out[#out + 1] = candidate.keyword
    end
    return table.concat(out, ",")
end

local function markersOf(candidates)
    local out = {}
    for _, candidate in ipairs(candidates) do
        out[#out + 1] = candidate.keyword .. ":" .. candidate.marker
    end
    return table.concat(out, ",")
end

-- 1. The case the diagnostic exists for ---------------------------------------------------------

local report = InviteTrade.describeMatch("wtb port from sw to if")

check(report.commonPhrase == "wtb port", "the common phrase should be reported, got " .. tostring(report.commonPhrase))
check(report.intentKeyword == "wtb", "intent should be reported")
check(report.serviceKeyword == "port", "service should be reported")
check(keywordsOf(report.candidates) == "sw,if", "both locations should be listed in message order")
check(markersOf(report.candidates) == "sw:origin,if:destination",
    "each location should be marked origin or destination, got " .. markersOf(report.candidates))
check(report.decision == "if", "the decision should be the destination-marked city")
check(report.portal.locationName == "Ironforge", "the decision should resolve to Ironforge")
check(report.portal.canonical == "Ironforge", "the resolution should come from the alias map")
check(report.originOnly == false, "a marked destination is not origin-only")
check(report.wouldInvite == true, "this request should invite")

-- 2. Origin-only phrasing is explained, not silently dropped ------------------------------------

report = InviteTrade.describeMatch("wtb portal in sw")
check(report.decision == "sw", "an origin-worded request still keeps the city as a fallback")
check(report.originOnly == true, "the report should say every location looked like an origin")
check(report.wouldInvite == true, "an origin-worded request must still invite")

-- 3. The report agrees with the matcher on the misrouting keywords ------------------------------

report = InviteTrade.describeMatch("wtb portal org")
check(report.decision == "org", "org should be the decision")
check(report.portal.locationName == "Orgrimmar", "org must report Orgrimmar, not Ironforge")

-- 4. Aliases for one city are shown merged ------------------------------------------------------

report = InviteTrade.describeMatch("wtb port to if, im in sw and stormwind")
check(keywordsOf(report.candidates) == "if,sw,stormwind", "every named location is listed before merging")
check(table.concat(report.deduped, ",") == "if,sw", "aliases for one city merge, got " ..
    table.concat(report.deduped, ","))

-- 5. Non-matching chatter ------------------------------------------------------------------------

report = InviteTrade.describeMatch("it goes from sw to if")
check(report.commonPhrase == nil, "ordinary conversation should not match a common phrase")
check(report.intentKeyword == nil, "no intent keyword in ordinary conversation")
check(report.wouldInvite == false, "ordinary conversation must not invite")
check(#report.candidates == 2, "locations are still reported so the user can see why it was close")

-- Intent without service is the recruitment-advert case.
report = InviteTrade.describeMatch("lf a hunter for our raid roster")
check(report.intentKeyword == "lf", "intent should be found")
check(report.serviceKeyword == nil, "no service keyword")
check(report.wouldInvite == false, "intent alone must not invite")

-- 6. Settings that block an otherwise good match are named --------------------------------------

Config.Settings.requireDestination = true
report = InviteTrade.describeMatch("wtb portal please")
check(report.matched == true, "the phrase still matched")
check(report.wouldInvite == false, "but Require Destination should block it")
check(report.blocked ~= nil and report.blocked:find("Require Destination"),
    "the report should name Require Destination as the blocker, got " .. tostring(report.blocked))
Config.Settings.requireDestination = false

Config.Settings.KeywordBanList = {"scam"}
report = InviteTrade.describeMatch("wtb portal sw scam")
check(report.wouldInvite == false, "a banned keyword should block the invite")
check(report.blocked ~= nil and report.blocked:find("banned"), "the report should name the banned keyword")
Config.Settings.KeywordBanList = {}

-- Smart matching off means only common phrases count.
Config.Settings.disableSmartMatching = true
report = InviteTrade.describeMatch("need a tp to org")
check(report.wouldInvite == false, "with smart matching off, a non-phrase request must not invite")
Config.Settings.disableSmartMatching = false
report = InviteTrade.describeMatch("need a tp to org")
check(report.wouldInvite == true, "with smart matching on, intent before service should invite")

-- 7. Empty and junk input do not error -----------------------------------------------------------

report = InviteTrade.describeMatch("")
check(report.wouldInvite == false, "an empty message invites nobody")
check(#report.candidates == 0, "an empty message names no locations")

report = InviteTrade.describeMatch("!!! ??? %%%")
check(report.wouldInvite == false, "punctuation invites nobody")

-- ------------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("parse report: %d check(s) failed", failures))
end

print("parse report: markers, decisions, alias merging, blockers and junk input all passed")
