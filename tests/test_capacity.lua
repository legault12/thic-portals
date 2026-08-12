-- Standalone regression tests for group capacity and the invite gate.
--
-- maxSimultaneousTickets defaults to 15, but a party seats four customers however that setting is
-- configured. Nothing checked the group, so past four the addon kept firing invites that could not
-- succeed, and each failed invite still created a record that blocked the customer from asking
-- again until it expired.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_capacity.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

_G.Config = {
    Settings = {
        debugMode = false,
        DestinationKeywords = {"sw", "stormwind", "if", "ironforge", "org"},
        IntentKeywords = {"wtb"},
        ServiceKeywords = {"portal", "port"},
        commonPhrases = {"wtb portal", "wtb port"},
        KeywordBanList = {},
        BanList = {},
        soundEnabled = false,
        removeRealmFromInviteCommand = false,
        inviteCooldown = 300,
        maxSimultaneousTickets = 15,
        disableSmartMatching = false,
        requireDestination = false
    },
    Portals = {"Portal: Stormwind", "Portal: Ironforge", "Portal: Orgrimmar"}
}

local now = 10000
local groupSize = 0
local inRaid = false
local invited = {}
local printed = {}

_G.time = function()
    return now
end
_G.GetTime = function()
    return now
end
_G.GetNumGroupMembers = function()
    return groupSize
end
_G.IsInRaid = function()
    return inRaid
end
_G.MEMBERS_PER_RAID_GROUP = 5
_G.MAX_RAID_MEMBERS = 40
_G.UnitFactionGroup = function()
    return "Alliance"
end
_G.InviteUnit = function(name)
    invited[#invited + 1] = name
end
_G.SendChatMessage = function()
end
_G.C_Timer = {
    After = function()
    end
}
_G.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    printed[#printed + 1] = table.concat(parts, " ")
end

_G.Events = {
    pendingInvites = {}
}

local Utils = dofile(addonDirectory .. "/Utils.lua")
local InviteTrade = dofile(addonDirectory .. "/InviteTrade.lua")
_G.UI = {
    setIconSpell = function()
    end
}

local failures = 0
local realPrint = io.write

local function check(condition, message)
    if not condition then
        failures = failures + 1
        realPrint("  FAIL: " .. message .. "\n")
    end
end

local function reset()
    now = 10000
    groupSize = 0
    inRaid = false
    invited = {}
    printed = {}
    Events.pendingInvites = {}
    InviteTrade.capacityNoticeShown = false
end

local function said(fragment)
    for _, line in ipairs(printed) do
        if line:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

-- 1. Raw capacity ---------------------------------------------------------------------------------

reset()
local free, used, maximum = Utils.getGroupCapacity()
check(free == 4 and used == 1 and maximum == 5, "solo should be 1 of 5 with 4 free, got " .. free .. "/" .. used)

groupSize = 3 -- the mage plus two customers
free, used = Utils.getGroupCapacity()
check(free == 2 and used == 3, "a party of three should have two seats free, got " .. free)

groupSize = 5
free = Utils.getGroupCapacity()
check(free == 0, "a full party has no seats free, got " .. free)

groupSize = 7 -- defensive: never report negative headroom
free = Utils.getGroupCapacity()
check(free == 0, "an over-full group should clamp to zero, got " .. free)

inRaid = true
groupSize = 12
free, used, maximum = Utils.getGroupCapacity()
check(maximum == 40 and free == 28, "a raid should seat forty, got " .. free .. " free of " .. maximum)
inRaid = false

-- 2. Invites already out hold a seat ---------------------------------------------------------------

reset()
groupSize = 3 -- two seats free

local function outstandingInvite(name, at)
    Events.pendingInvites[name] = {
        name = name,
        fullName = name,
        hasJoined = false,
        timestamp = at
    }
end

local slots, capacityFree, outstanding = Utils.availableInviteSlots(Events.pendingInvites)
check(slots == 2 and outstanding == 0, "no invites out means every free seat is offerable, got " .. slots)

outstandingInvite("Anna", now)
slots, capacityFree, outstanding = Utils.availableInviteSlots(Events.pendingInvites)
check(slots == 1 and outstanding == 1, "an invite already out should hold a seat, got " .. slots)

outstandingInvite("Boris", now)
slots = Utils.availableInviteSlots(Events.pendingInvites)
check(slots == 0, "two invites out fill the two free seats, got " .. slots)

-- An invite old enough that WoW's own popup has lapsed stops holding its seat.
now = now + Utils.INVITE_SEAT_HOLD + 1
slots, capacityFree, outstanding = Utils.availableInviteSlots(Events.pendingInvites)
check(outstanding == 0, "a lapsed invite should stop holding a seat, got " .. outstanding)
check(slots == 2, "the seats should come back, got " .. slots)

-- Customers who have joined are already counted by the group itself, so they must not be
-- double-counted as outstanding invites.
reset()
groupSize = 3
Events.pendingInvites["Anna"] = {
    name = "Anna",
    hasJoined = true,
    timestamp = now
}
slots, capacityFree, outstanding = Utils.availableInviteSlots(Events.pendingInvites)
check(outstanding == 0, "a joined customer is not an outstanding invite")
check(slots == 2, "a joined customer must not be counted twice, got " .. slots)

-- Reset the group explicitly rather than inheriting it from the case above.
reset()
check(select(1, Utils.availableInviteSlots(nil)) == 4, "a nil queue solo should report four seats")
groupSize = 3
check(select(1, Utils.availableInviteSlots(nil)) == 2, "a nil queue still reports the group's own capacity")
check(select(1, Utils.availableInviteSlots({})) == 2, "an empty queue behaves the same as no queue")

-- 3. The gate: no seat, no invite -------------------------------------------------------------------

reset()
groupSize = 5 -- full party

InviteTrade.handleInviteAndMessage("Newcomer", "Newcomer", "MAGE", "wtb portal sw", false)

check(#invited == 0, "a full group must not send an invite")
check(Events.pendingInvites["Newcomer"] == nil,
    "a refused invite must not leave a record burning the customer's cooldown")
check(said("Group is full"), "the user should be told the shop is turning people away")

-- The notice is shown once, not on every request that arrives while full.
printed = {}
InviteTrade.handleInviteAndMessage("Another", "Another", "MAGE", "wtb portal sw", false)
check(said("Group is full") == false, "the full-group notice should not repeat for every request")
check(#invited == 0, "still no invite while full")

-- A seat opening up lets the next customer in, and re-arms the notice.
groupSize = 4
InviteTrade.handleInviteAndMessage("Lucky", "Lucky", "MAGE", "wtb portal sw", false)

check(#invited == 1 and invited[1] == "Lucky", "a free seat should invite, got " .. tostring(invited[1]))
check(Events.pendingInvites["Lucky"] ~= nil, "an accepted invite should be tracked")
check(InviteTrade.capacityNoticeShown == false, "the notice should re-arm once the group has room")

-- Filling again warns again.
groupSize = 5
printed = {}
InviteTrade.handleInviteAndMessage("Late", "Late", "MAGE", "wtb portal sw", false)
check(said("Group is full"), "the notice should return the next time the group fills")

-- 4. Outstanding invites gate too, not just bodies in the group -------------------------------------

reset()
groupSize = 4 -- one seat free

InviteTrade.handleInviteAndMessage("First", "First", "MAGE", "wtb portal sw", false)
check(#invited == 1, "the free seat should be offered to the first customer")

InviteTrade.handleInviteAndMessage("Second", "Second", "MAGE", "wtb portal sw", false)
check(#invited == 1, "the seat is spoken for, so the second customer must not be invited")
check(Events.pendingInvites["Second"] == nil, "and must not be left with a record")

-- Once the first invite lapses, the seat is offered again.
now = now + Utils.INVITE_SEAT_HOLD + 1
InviteTrade.handleInviteAndMessage("Third", "Third", "MAGE", "wtb portal sw", false)
check(#invited == 2 and invited[2] == "Third", "a lapsed invite should free the seat, got " .. tostring(invited[2]))

-- 5. A raid does not hit the party ceiling ----------------------------------------------------------

reset()
inRaid = true
groupSize = 6

InviteTrade.handleInviteAndMessage("Raider", "Raider", "MAGE", "wtb portal sw", false)
check(#invited == 1, "a raid has room well past four customers")

-- ------------------------------------------------------------------------------------------------

if failures > 0 then
    error(string.format("capacity: %d check(s) failed", failures))
end

realPrint("capacity: group seats, invite holds, the full-group gate and raid headroom all passed\n")
