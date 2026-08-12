-- Standalone regression tests for customers tracked in a raid rather than a party.
--
-- Raid conversion lifted the ceiling from four customers to thirty-nine, but everything built on
-- locating a customer resolved them through party1-4 only. In a raid those tokens cover just your
-- own subgroup, so every customer outside it would have read as having left: tickets torn down,
-- locations unknown, travel buttons gone, auto-completion never firing.
--
-- These run the same customer through the same features in both group shapes and require identical
-- answers.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_raid_group.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false,
        autoCompleteOnArrival = true,
        DestinationKeywords = {"sw", "if", "org"},
        distanceInferringClose = 50,
        soundEnabled = false
    },
    Portals = {"Portal: Stormwind", "Portal: Ironforge"}
}

local now = 3000
local inRaid = false
local groupSize = 0
local roster = {} -- token -> name
local zones = {} -- token -> zone
local positions = {} -- token -> {x, y, instance}
local uninvited = {}

_G.time = function()
    return now
end
_G.GetTime = function()
    return now
end
_G.MAX_PARTY_MEMBERS = 4
_G.MAX_RAID_MEMBERS = 40
_G.IsInRaid = function()
    return inRaid
end
_G.GetNumGroupMembers = function()
    return groupSize
end
_G.UnitExists = function(token)
    return roster[token] ~= nil
end
_G.UnitName = function(token)
    return roster[token], ""
end
_G.GetRealmName = function()
    return "Spineshatter"
end
_G.UnitPosition = function(unit)
    local spot = positions[unit]
    if not spot then
        return nil
    end
    return spot[1], spot[2], spot[3]
end
_G.C_Map = {
    GetBestMapForUnit = function(unit)
        return zones[unit] and unit or nil
    end,
    GetMapInfo = function(unit)
        return {
            name = zones[unit]
        }
    end
}
_G.GetSpellBookItemName = function(index)
    return ({"Teleport: Darnassus"})[index]
end
_G.BOOKTYPE_SPELL = "spell"
_G.UnitFactionGroup = function()
    return "Alliance"
end
_G.UninviteUnit = function(name)
    uninvited[#uninvited + 1] = name
end
_G.SendChatMessage = function()
end
_G.C_Timer = {
    After = function()
    end
}
_G.UI = {
    updateTicketList = function()
    end,
    updateTicketFrame = function()
    end
}

local realPrint = print
_G.print = function()
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
        realPrint("  FAIL: " .. message)
    end
end

-- Put Gralint in a party, or in a raid well outside our own subgroup.
local function place(shape, customerZone)
    uninvited = {}
    positions = {
        player = {0, 0, 1}
    }

    if shape == "party" then
        inRaid = false
        groupSize = 2
        roster = {
            party1 = "Gralint"
        }
        zones = {
            player = "Stormwind City",
            party1 = customerZone
        }
        positions.party1 = {30, 40, 1} -- 50 yards
    else
        inRaid = true
        groupSize = 12
        roster = {
            raid7 = "Gralint"
        }
        zones = {
            player = "Stormwind City",
            raid7 = customerZone
        }
        positions.raid7 = {30, 40, 1}
    end

    Events.pendingInvites = {
        Gralint = {
            name = "Gralint",
            fullName = "Gralint-Spineshatter",
            destination = "if",
            timestamp = 2900,
            joinedAt = 2900,
            portalCastAt = 2950
        }
    }
end

-- Every question the addon asks about a customer, asked in one shape.
local function interrogate(shape, customerZone)
    place(shape, customerZone)

    local zone, city = Utils.getCustomerLocation("Gralint")

    return {
        token = Utils.getGroupUnitToken("Gralint"),
        inGroup = Utils.isInGroup("Gralint"),
        zone = zone,
        city = city,
        nearby = Utils.isPlayerWithinRange("Gralint", 60),
        teleport = city and Utils.getKnownTeleportSpell(city) or nil,
        queued = #Utils.buildQueueOverview(Events.pendingInvites)
    }
end

-- 1. The same customer, the same answers, whichever shape the group is -----------------------------

local inParty = interrogate("party", "Darnassus")
local inRaidGroup = interrogate("raid", "Darnassus")

check(inParty.token == "party1", "a party customer resolves to a party token, got " .. tostring(inParty.token))
check(inRaidGroup.token == "raid7", "a raid customer resolves to their raid token, got " ..
    tostring(inRaidGroup.token))

check(inParty.inGroup == true, "a party customer is in the group")
check(inRaidGroup.inGroup == true, "a raid customer is STILL in the group - this is the bug conversion caused")

check(inRaidGroup.zone == inParty.zone, "location should be found in a raid too, got " ..
    tostring(inRaidGroup.zone))
check(inRaidGroup.city == "Darnassus", "the city should resolve in a raid, got " .. tostring(inRaidGroup.city))
check(inRaidGroup.nearby == inParty.nearby, "distance should measure the same in a raid")
check(inRaidGroup.nearby == true, "and should actually find them, at 50 yards inside a 60 yard range")
check(inRaidGroup.teleport == "Teleport: Darnassus", "the travel option should survive conversion, got " ..
    tostring(inRaidGroup.teleport))
check(inRaidGroup.queued == 1, "the customer should appear in the queue overview, got " .. inRaidGroup.queued)

-- 2. Joining and leaving read correctly in a raid ----------------------------------------------------

place("raid", "Darnassus")
check(Utils.isInGroup("Gralint") == true, "a raid customer counts as present")

-- Somebody genuinely not in the group still reads as absent, in both shapes.
check(Utils.isInGroup("Nobody") == false, "a stranger is not in the raid")
place("party", "Darnassus")
check(Utils.isInGroup("Nobody") == false, "a stranger is not in the party")

-- A raid larger than the reported size is not scanned past its end.
inRaid = true
groupSize = 3
roster = {
    raid7 = "Gralint"
}
check(Utils.isInGroup("Gralint") == false, "a member beyond the reported roster size is not found")

-- 3. Auto-completion works for a raid customer --------------------------------------------------------

place("raid", "Ironforge") -- they asked for "if" and are now standing in Ironforge

check(InviteTrade.completeIfArrived("Gralint") == true, "a raid customer should auto-complete on arrival")
check(Events.pendingInvites.Gralint == nil, "their ticket should close")
check(uninvited[1] == "Gralint-Spineshatter", "and they should be dropped from the raid")

-- Still travelling, in a raid, stays open just as in a party.
place("raid", "Stormwind City")
check(InviteTrade.completeIfArrived("Gralint") == false, "a raid customer who has not arrived stays open")
check(Events.pendingInvites.Gralint ~= nil, "their ticket should survive")

-- 4. The proximity watcher does not tear down a raid customer -------------------------------------------

-- Its "have they left" test is the same membership helper, so a raid customer must not be dropped.
place("raid", "Darnassus")
check(Utils.isInGroup("Gralint") == true,
    "the watcher's membership test must hold for a raid customer, or their ticket is deleted a second after conversion")

-- ------------------------------------------------------------------------------------------------

_G.print = realPrint

if failures > 0 then
    error(string.format("raid group: %d check(s) failed", failures))
end

print("raid group: token resolution, membership, location, distance, travel and auto-complete all passed")
