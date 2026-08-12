-- Standalone regression tests for the /Tp ticket commands.
--
-- These drive the real handleCommand from ThicPortals.lua rather than reimplementing the argument
-- parsing, because the parsing is most of what can go wrong. The addon file is loaded against
-- stubbed WoW globals; anything it touches at load (CreateFrame, RegisterEvent, SlashCmdList) is
-- faked here.
--
-- Run from any directory with: lua /path/to/ThicPortals/tests/test_commands.lua

local scriptPath = debug.getinfo(1, "S").source:sub(2)
local scriptDirectory = scriptPath:match("^(.*[/\\])") or "./"
local addonDirectory = scriptDirectory .. ".."

local keywords = {"darn", "darnassus", "sw", "stormwind", "if", "ironforge", "org", "orgrimmar", "shatt", "uc",
                  "mytown"}

_G.Config = {
    Settings = {
        debugMode = false,
        DestinationKeywords = keywords,
        IntentKeywords = {"wtb"},
        ServiceKeywords = {"portal", "port"},
        commonPhrases = {"wtb portal"},
        KeywordBanList = {},
        BanList = {},
        soundEnabled = false,
        removeRealmFromInviteCommand = false,
        inviteCooldown = 300,
        disableSmartMatching = false,
        requireDestination = false
    },
    Portals = {"Portal: Darnassus", "Portal: Stormwind", "Portal: Ironforge", "Portal: Orgrimmar",
               "Portal: Undercity", "Portal: Shattrath"}
}

-- WoW globals ------------------------------------------------------------------------------------

local output = {}
local realPrint = print

_G.print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(index, ...)))
    end
    output[#output + 1] = table.concat(parts, " ")
end

local grouped = {}
local invited = {}
local timers = {}
local clock = 5000

_G.time = function()
    return clock
end
_G.GetTime = function()
    return clock
end
_G.UnitInParty = function(name)
    return grouped[name] == true
end
_G.UnitFactionGroup = function()
    return "Alliance"
end
_G.InviteUnit = function(name)
    invited[#invited + 1] = name
end
_G.SendChatMessage = function()
end
_G.C_Timer = {
    After = function(delay, callback)
        timers[#timers + 1] = {
            delay = delay,
            callback = callback
        }
    end
}
_G.CreateFrame = function()
    return {
        RegisterEvent = function()
        end,
        SetScript = function()
        end
    }
end
_G.SlashCmdList = {}

local uiCalls = {}

_G.UI = {
    showPaginatedTicketWindow = function()
        uiCalls[#uiCalls + 1] = "show"
    end,
    updateTicketList = function()
        uiCalls[#uiCalls + 1] = "list"
    end,
    updateTicketFrame = function()
        uiCalls[#uiCalls + 1] = "frame"
    end
}

local Utils = dofile(addonDirectory .. "/Utils.lua")
local InviteTrade = dofile(addonDirectory .. "/InviteTrade.lua")

_G.Events = {
    pendingInvites = {},
    onEvent = function()
    end
}

dofile(addonDirectory .. "/ThicPortals.lua")

local failures = 0

local function check(condition, message)
    if not condition then
        failures = failures + 1
        realPrint("  FAIL: " .. message)
    end
end

local function run(command)
    output = {}
    uiCalls = {}
    handleCommand(command)
end

local function said(fragment)
    for _, line in ipairs(output) do
        if line:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

local function reset()
    _G.Events.pendingInvites = {}
    invited = {}
    timers = {}
    grouped = {}
    InviteTrade.pendingTravelAnnouncement = nil
end

-- 1. Adding a customer who is not grouped invites them -------------------------------------------

reset()
run("add Gralint if")

local ticket = Events.pendingInvites["Gralint"]
check(ticket ~= nil, "an ungrouped add should create a ticket")
check(invited[1] == "Gralint", "an ungrouped add should send an invite, got " .. tostring(invited[1]))
check(ticket.hasJoined == false, "an ungrouped customer has not joined yet")
check(ticket.destination == "if", "the supplied destination should be stored")
check(ticket.destinationLocked == true, "a destination given by hand should be locked")
check(said("Invited and now tracking"), "the command should confirm the invite")

-- 2. Adding a customer already in the group adopts them without re-inviting -----------------------

reset()
grouped["Keefs"] = true
run("add Keefs org")

ticket = Events.pendingInvites["Keefs"]
check(ticket ~= nil, "a grouped add should create a ticket")
check(#invited == 0, "a grouped customer must not be re-invited")
check(ticket.hasJoined == true, "a grouped customer counts as joined")
check(uiCalls[#uiCalls] == "show", "adopting a grouped customer should show the ticket window")
check(said("already in the party"), "the command should say they were adopted")

-- 3. Adding a name that is already tracked is refused --------------------------------------------

reset()
run("add Gralint if")
Events.pendingInvites["Gralint"].hasPaid = true
Events.pendingInvites["Gralint"].travelled = true
invited = {}

run("add Gralint org")

check(said("already tracked"), "a duplicate add should be refused")
check(Events.pendingInvites["Gralint"].destination == "if", "a refused add must not change the destination")
check(Events.pendingInvites["Gralint"].hasPaid == true, "a refused add must not discard payment state")
check(Events.pendingInvites["Gralint"].travelled == true, "a refused add must not discard travel state")
check(#invited == 0, "a refused add must not send another invite")

-- The refusal points at the commands that can do what was probably meant.
check(said("/Tp destination") and said("/Tp remove"), "the refusal should name the alternatives")

-- A realm-qualified duplicate of a tracked short name is also refused.
run("add Gralint-Otherrealm if")
check(said("already tracked"), "a realm-qualified duplicate of a tracked name should also be refused")

-- 4. Destinations are validated before a ticket is built ------------------------------------------

reset()
run("add Bob zzzzz")

check(Events.pendingInvites["Bob"] == nil, "an unresolvable destination must not create a ticket")
check(#invited == 0, "an unresolvable destination must not send an invite")
check(said("not a destination this addon can resolve"), "the refusal should explain why")

-- A configured custom keyword is accepted.
reset()
run("add Bob mytown")
check(Events.pendingInvites["Bob"] ~= nil, "a configured custom keyword should be accepted")
check(Events.pendingInvites["Bob"].destination == "mytown", "the custom keyword should be stored")

-- No destination at all is fine; it gets filled in later.
reset()
run("add Bob")
check(Events.pendingInvites["Bob"] ~= nil, "adding without a destination should work")
check(Events.pendingInvites["Bob"].destination == nil, "no destination means none stored")
check(Events.pendingInvites["Bob"].destinationLocked == nil, "nothing to lock when none was given")

-- 5. Cross-realm names keep their realm for whispering -------------------------------------------

reset()
run("add Keefs-Spineshatter if")

ticket = Events.pendingInvites["Keefs"]
check(ticket ~= nil, "the ticket should be keyed by the short name")
check(ticket.fullName == "Keefs-Spineshatter", "the full Name-Realm must be preserved for whispers, got " ..
    tostring(ticket and ticket.fullName))
check(ticket.name == "Keefs", "the display name should be the short name")
check(invited[1] == "Keefs-Spineshatter", "the invite should use the full name")

-- 6. Removal clears tracking and any armed announcement ------------------------------------------

reset()
run("add Gralint if")
InviteTrade.beginTravelAnnouncement("Gralint", Events.pendingInvites["Gralint"], "Darnassus", "Teleport: Darnassus")
check(InviteTrade.pendingTravelAnnouncement ~= nil, "precondition: an announcement is armed")

run("remove Gralint")

check(Events.pendingInvites["Gralint"] == nil, "remove should drop the ticket")
check(InviteTrade.pendingTravelAnnouncement == nil, "remove should clear the armed announcement")
check(said("Stopped tracking"), "remove should confirm")
check(said("still in the party"), "remove should be explicit that it does not kick")

local sawListRefresh = false
for _, call in ipairs(uiCalls) do
    if call == "list" then
        sawListRefresh = true
    end
end
check(sawListRefresh, "remove should refresh the ticket list")

-- Removing something untracked says so rather than failing silently.
run("remove Nobody")
check(said("No ticket found"), "removing an untracked name should report it")

-- A realm-qualified name resolves to the tracked short name.
reset()
run("add Keefs-Spineshatter if")
run("remove Keefs-Spineshatter")
check(Events.pendingInvites["Keefs"] == nil, "a realm-qualified remove should find the short-name ticket")

-- 7. Setting a destination locks it ---------------------------------------------------------------

reset()
run("add Gralint")
run("destination Gralint org")

ticket = Events.pendingInvites["Gralint"]
check(ticket.destination == "org", "the destination should be set")
check(ticket.destinationLocked == true, "setting a destination by hand should lock it")
check(said("Orgrimmar"), "the confirmation should name the resolved city")
check(said("locked"), "the confirmation should say it is locked")

-- Invalid destinations are refused here too, leaving the ticket untouched.
run("destination Gralint zzzzz")
check(Events.pendingInvites["Gralint"].destination == "org", "an invalid destination must not overwrite a good one")
check(said("not a destination this addon can resolve"), "the refusal should explain why")

run("destination Nobody if")
check(said("No ticket found"), "setting a destination on an untracked name should report it")

-- 8. Listing ---------------------------------------------------------------------------------------

reset()
check(true, "sanity")
run("list")
check(said("No tickets are being tracked"), "an empty queue should say so")

run("add Gralint if")
clock = clock + 95 -- 1m 35s later
run("list")

check(said("Gralint"), "the list should name the customer")
check(said("if"), "the list should show the destination")
check(said("invited"), "the list should show the state")
check(said("1m 35s"), "the list should show how long they have waited")
check(said("(locked)"), "the list should flag a locked destination")
check(said("1 ticket(s) tracked"), "the list should report the count")

grouped["Gralint"] = true
Events.pendingInvites["Gralint"].hasJoined = true
run("list")
check(said("joined"), "state should follow the ticket")

Events.pendingInvites["Gralint"].hasPaid = true
run("list")
check(said("paid"), "a paid ticket should read as paid")

Events.pendingInvites["Gralint"].travelled = true
run("list")
check(said("complete"), "a travelled ticket should read as complete")

-- 8b. Queue ordering ------------------------------------------------------------------------------

-- Oldest request first, regardless of name or hash order. Alphabetical ordering used to decide
-- service order, and pairs() left /Tp list in whatever order the table felt like.
reset()
clock = 1000
run("add Zeta if")
clock = 1010
run("add Alpha if")
clock = 1020
run("add Mid if")

local ordered = Utils.orderTicketsByArrival(Events.pendingInvites, false)
check(table.concat(ordered, ",") == "Zeta,Alpha,Mid",
    "tickets should be ordered oldest first, got " .. table.concat(ordered, ","))

-- Only joined customers get a ticket in the window.
Events.pendingInvites["Alpha"].hasJoined = true
Events.pendingInvites["Mid"].hasJoined = true
check(table.concat(Utils.orderTicketsByArrival(Events.pendingInvites, true), ",") == "Alpha,Mid",
    "the window queue should only contain joined customers")

-- Same-second arrivals order deterministically rather than by hash.
reset()
clock = 2000
run("add Yolanda if")
run("add Bert if")
run("add Malcolm if")
check(table.concat(Utils.orderTicketsByArrival(Events.pendingInvites, false), ",") == "Bert,Malcolm,Yolanda",
    "ties should break on name so the queue is stable")

check(#Utils.orderTicketsByArrival({}, false) == 0, "an empty queue orders to nothing")
check(#Utils.orderTicketsByArrival(nil, false) == 0, "a nil queue orders to nothing")

-- A ticket with no timestamp sorts first rather than erroring.
local mixed = {
    Old = {
        timestamp = 5
    },
    Untimed = {}
}
check(table.concat(Utils.orderTicketsByArrival(mixed, false), ",") == "Untimed,Old",
    "a ticket without a timestamp must not break ordering")

-- The list output follows the same order.
reset()
clock = 3000
run("add Zeta if")
clock = 3060
run("add Alpha if")
run("list")

local zetaLine, alphaLine
for index, line in ipairs(output) do
    if line:find("Zeta", 1, true) then
        zetaLine = index
    end
    if line:find("Alpha", 1, true) then
        alphaLine = index
    end
end
check(zetaLine and alphaLine and zetaLine < alphaLine, "/Tp list should print the oldest ticket first")

-- The displayed ticket is followed by name, not by position, so a queue that reorders underneath
-- cannot page the user onto somebody else mid-click.
local queue = {"Bert", "Malcolm", "Yolanda"}
check(Utils.indexOfTicket(queue, "Malcolm") == 2, "a present sender should be found")
check(Utils.indexOfTicket(queue, "Bert") == 1, "the first sender should be found")
check(Utils.indexOfTicket(queue, "Gone") == nil, "a departed sender should not be found")
check(Utils.indexOfTicket({}, "Bert") == nil, "an empty queue finds nobody")
check(Utils.indexOfTicket(nil, "Bert") == nil, "a nil queue finds nobody")
check(Utils.indexOfTicket(queue, nil) == nil, "a nil sender finds nothing")

-- After the ticket ahead of them leaves, the customer being handled keeps their position.
local before = {"Bert", "Malcolm", "Yolanda"}
local after = {"Malcolm", "Yolanda"}
check(Utils.indexOfTicket(before, "Malcolm") == 2 and Utils.indexOfTicket(after, "Malcolm") == 1,
    "following by name should track the customer across a reorder")

-- 8c. Wait formatting ------------------------------------------------------------------------------

check(Utils.formatWaitTime(0) == "0s", "zero reads as seconds")
check(Utils.formatWaitTime(47) == "47s", "under a minute reads as seconds")
check(Utils.formatWaitTime(60) == "1m 00s", "a minute reads as minutes and seconds")
check(Utils.formatWaitTime(139) == "2m 19s", "two minutes nineteen, got " .. Utils.formatWaitTime(139))
check(Utils.formatWaitTime(3599) == "59m 59s", "just under an hour still reads as minutes")
check(Utils.formatWaitTime(3600) == "1h 00m", "an hour switches to hours and minutes")
check(Utils.formatWaitTime(7565) == "2h 06m", "long waits read as hours, got " .. Utils.formatWaitTime(7565))
check(Utils.formatWaitTime(-5) == "0s", "a negative wait clamps to zero")
check(Utils.formatWaitTime(nil) == "0s", "a missing wait reads as zero")

-- 9. Usage messages --------------------------------------------------------------------------------

run("add")
check(said("Usage: /Tp add"), "add with no arguments should print usage")

run("destination Gralint")
check(said("Usage: /Tp destination"), "destination with one argument should print usage")

run("parse")
check(said("Usage: /Tp parse"), "parse with no argument should print usage")

-- ------------------------------------------------------------------------------------------------

_G.print = realPrint

if failures > 0 then
    error(string.format("commands: %d check(s) failed", failures))
end

print("commands: add, remove, destination, list, ordering, wait formatting and validation all passed")
