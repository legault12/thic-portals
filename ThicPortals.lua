-- ThicPortals.lua
local ThicPortals = {}

Config = _G.Config
InviteTrade = _G.InviteTrade
UI = _G.UI
Events = _G.Events
Utils = _G.Utils

local frame = CreateFrame("Frame")

-- Register event handlers
frame:RegisterEvent("CHAT_MSG_SAY")
frame:RegisterEvent("CHAT_MSG_YELL")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_CHANNEL")
frame:RegisterEvent("PARTY_INVITE_REQUEST")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("TRADE_SHOW")
frame:RegisterEvent("TRADE_ACCEPT_UPDATE")
frame:RegisterEvent("TRADE_MONEY_CHANGED")
frame:RegisterEvent("TRADE_TARGET_ITEM_CHANGED")
frame:RegisterEvent("TRADE_CLOSED")
frame:RegisterEvent("VARIABLES_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UI_INFO_MESSAGE")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Set the event handler function
frame:SetScript("OnEvent", Events.onEvent)


-- Tickets are keyed by short name; commands accept either "Player" or "Player-Realm".
local function findTicket(name)
    if not name or name == "" then
        return nil, nil
    end

    local shortName = name:match("^([^%-]+)") or name

    for sender, inviteData in pairs(Events.pendingInvites) do
        if sender:lower() == shortName:lower() then
            return sender, inviteData
        end
    end

    return nil, nil
end

local function describeTicketState(inviteData)
    if inviteData.travelled then
        return "complete"
    elseif inviteData.hasPaid then
        return "paid"
    elseif inviteData.hasJoined then
        return "joined"
    end

    return "invited"
end

-- /Tp parse - explain what the matcher makes of a message.
local function printParse(message)
    local report = InviteTrade.describeMatch(message)

    Utils.print("Parse: \"" .. message .. "\"")

    print("  Common phrase: " .. (report.commonPhrase or "no match"))
    print("  Intent: " .. (report.intentKeyword and (report.intentKeyword .. " (pos " .. report.intentPosition .. ")") or
              "none") .. "   Service: " ..
              (report.serviceKeyword and (report.serviceKeyword .. " (pos " .. report.servicePosition .. ")") or "none"))

    if #report.candidates == 0 then
        print("  Locations named: none")
    else
        local parts = {}

        for _, candidate in ipairs(report.candidates) do
            local note = candidate.canonical or "unmapped"

            if candidate.marker ~= "none" then
                note = note .. ", " .. candidate.marker
            end

            parts[#parts + 1] = candidate.keyword .. " (" .. note .. ")"
        end

        print("  Locations named: " .. table.concat(parts, ", "))
        print("  After alias merge: " .. table.concat(report.deduped, ", "))
    end

    if report.decision then
        local portal = report.portal
        local how = portal and (portal.canonical and "alias map" or "heuristic fallback") or "unresolved"

        print("  Decision: " .. report.decision .. " -> " .. (portal and portal.locationName or "?") .. " (" .. how ..
                  ")")

        if report.originOnly then
            print("  Note: every location named looks like where they ARE, not where they are going.")
            print("        Kept as a fallback so the customer is not dropped.")
        end
    else
        print("  Decision: no destination found")
    end

    if report.wouldInvite then
        print("  Would invite: yes")
    elseif report.blocked then
        print("  Would invite: no - " .. report.blocked)
    else
        print("  Would invite: no - nothing matched")
    end
end

-- Slash command handler function
function handleCommand(msg)
    local command, rest = msg:match("^(%S*)%s*(.-)$")

    if command == "on" then
        Config.Settings.addonEnabled = true
        Utils.print("Addon enabled.")
        UI.addonEnabledCheckbox:SetValue(true)
    elseif command == "off" then
        Config.Settings.addonEnabled = false
        Utils.print("Addon disabled.")
        UI.addonEnabledCheckbox:SetValue(false)
    elseif command == "show" then
        UI.showToggleButton()
        Utils.print("Addon management icon displayed.")
    elseif command == "reset" then
        UI.resetToggleButtonPosition()
        Utils.print("Addon management icon position reset.")
    elseif command == "msg" then
        Config.Settings.inviteMessage = rest
        Utils.print("Invite message set to: " .. rest)
    elseif command == "debug" then
        if rest == "on" then
            Config.Settings.debugMode = true
            Utils.print("Debug mode enabled.")
        elseif rest == "off" then
            Config.Settings.debugMode = false
            Utils.print("Debug mode disabled.")
        else
            Utils.print("Usage: /Tp debug on/off - Enable or disable debug mode")
        end
    elseif command == "keywords" then
        local action, keywordType, keyword = rest:match("^(%S*)%s*(%S*)%s*(.-)$")
        if action and keywordType and keyword and keyword ~= "" then
            local keywordTable
            if keywordType == "intent" then
                keywordTable = Config.Settings.IntentKeywords
            elseif keywordType == "destination" then
                keywordTable = Config.Settings.DestinationKeywords
            elseif keywordType == "service" then
                keywordTable = Config.Settings.ServiceKeywords
            else
                Utils.print("Invalid keyword type. Use 'intent', 'destination', or 'service'.")
                return
            end
            if action == "add" then
                table.insert(keywordTable, keyword)
                Utils.print("Added keyword to " .. keywordType .. ": " .. keyword)
            elseif action == "remove" then
                for i, k in ipairs(keywordTable) do
                    if k == keyword then
                        table.remove(keywordTable, i)
                        Utils.print("Removed keyword from " .. keywordType .. ": " .. keyword)
                        break
                    end
                end
            else
                Utils.print("Invalid action. Use 'add' or 'remove'.")
            end
        else
            Utils.print("Usage: /Tp keywords add/remove intent/destination/service [keyword]")
        end
    elseif command == "cooldown" then
        local seconds = tonumber(rest)
        if seconds then
            Config.Settings.inviteCooldown = seconds
            Utils.print("Invite cooldown set to " .. seconds .. " seconds.")
        else
            Utils.print("Usage: /Tp cooldown [seconds] - Set the invite cooldown period")
        end
    elseif command == "checkspells" then
        Utils.print("Scanning spellbook for Conjure spells...")
        local i = 1
        local foundFood = false
        local foundWater = false
        while i <= 1024 do
            local spellName, spellRank = GetSpellBookItemName(i, BOOKTYPE_SPELL)
            if not spellName then
                break
            end
            if spellName == "Conjure Food" or spellName == "Conjure Water" then
                Utils.print("Found: " .. spellName .. " (" .. (spellRank or "no rank") .. ")")
                if spellName == "Conjure Food" then
                    foundFood = true
                end
                if spellName == "Conjure Water" then
                    foundWater = true
                end
            end
            i = i + 1
        end
        if not foundFood and not foundWater then
            Utils.print("No Conjure spells found in spellbook!")
        end

        -- Debug: Check config structure
        if not Config.Settings.foodItems then
            Utils.print("ERROR: Config.Settings.foodItems is nil!")
        else
            Utils.print("Config has " .. #Config.Settings.foodItems .. " food items defined.")
            if #Config.Settings.foodItems > 0 then
                local item = Config.Settings.foodItems[1]
                Utils.print("Sample food item: name=" .. (item.name or "nil") .. ", spellName=" ..
                          (item.spellName or "nil") .. ", rank=" .. (item.rank or "nil"))
            end
        end

        if not Config.Settings.waterItems then
            Utils.print("ERROR: Config.Settings.waterItems is nil!")
        else
            Utils.print("Config has " .. #Config.Settings.waterItems .. " water items defined.")
        end

        local availableFood = Utils.getAvailableFoodItems()
        local availableWater = Utils.getAvailableWaterItems()
        Utils.print("Detected " .. #availableFood .. " food items and " .. #availableWater ..
                  " water items you can conjure.")

        -- Test the detection function directly
        local testResult = Utils.isSpellRankKnown("Conjure Food", 7)
        Utils.print("Direct test - isSpellRankKnown('Conjure Food', 7) = " .. tostring(testResult))
    elseif command == "parse" then
        if rest == "" then
            Utils.print("Usage: /Tp parse [message] - explain how a request would be matched")
        else
            printParse(rest)
        end
    elseif command == "list" then
        -- Oldest first, the same order the ticket window pages through.
        local ordered = Utils.orderTicketsByArrival(Events.pendingInvites, false)
        local count = #ordered

        for _, sender in ipairs(ordered) do
            local inviteData = Events.pendingInvites[sender]
            local waited = inviteData.timestamp and (time() - inviteData.timestamp) or 0

            print(string.format("  %-14s %-10s %-9s %8s%s", sender, inviteData.destination or "-",
                describeTicketState(inviteData), Utils.formatWaitTime(waited),
                inviteData.destinationLocked and "  (locked)" or ""))
        end

        local slots, free, outstanding, used, maximum = Utils.availableInviteSlots(Events.pendingInvites)

        if count == 0 then
            Utils.print("No tickets are being tracked.")
        else
            Utils.print(count .. " ticket(s) tracked.")
        end

        Utils.print(string.format("Group %d/%d, %d seat(s) free, %d invite(s) out, %d more can be invited.", used,
            maximum, free, outstanding, slots))
    elseif command == "add" then
        local name, destination = rest:match("^(%S+)%s*(.-)$")

        local shortName = name and (name:match("^([^%-]+)") or name)
        local alreadyTracked = shortName and findTicket(shortName)
        -- Someone already in the group is occupying a seat, so adopting them costs nothing and is
        -- allowed however full we are. Inviting somebody new goes through the same gate as the
        -- automatic path.
        local alreadyGrouped = shortName and UnitInParty(shortName)
        local roomToInvite, freeSeats, outstandingInvites = InviteTrade.hasInviteCapacity()

        if not name or name == "" then
            Utils.print("Usage: /Tp add [player] [destination] - track a customer the addon missed")
        elseif alreadyTracked then
            -- Overwriting would silently discard payment, lock, travel and announcement state.
            Utils.print(alreadyTracked .. " is already tracked. Use /Tp destination to change where " ..
                            "they are going, or /Tp remove to drop the ticket first.")
        elseif not alreadyGrouped and not roomToInvite then
            Utils.print("No room to invite " .. shortName .. ": " .. freeSeats .. " seat(s) free, " ..
                            outstandingInvites .. " invite(s) already out. Try again when a seat frees up.")
        elseif destination ~= "" and not Utils.isUsableDestination(destination) then
            Utils.print("'" .. destination .. "' is not a destination this addon can resolve. Add it " ..
                            "under Destination Keywords in the options panel, or leave it off and set " ..
                            "it later.")
        else
            InviteTrade.createPendingInvite(shortName, nil, name, "(added by hand)",
                destination ~= "" and destination or nil)

            if destination ~= "" then
                Events.pendingInvites[shortName].destinationLocked = true
            end

            if alreadyGrouped then
                -- Already in the group: this is recovery for a customer the addon lost track of.
                Events.pendingInvites[shortName].hasJoined = true
                UI.showPaginatedTicketWindow()
                Utils.print("Now tracking " .. shortName .. " (already in the party).")
            else
                InviteTrade.invitePlayer(name)
                Utils.print("Invited and now tracking " .. shortName .. ".")
            end
        end
    elseif command == "remove" then
        local sender = findTicket(rest)

        if not sender then
            Utils.print("No ticket found for '" .. rest .. "'. Try /Tp list.")
        else
            Events.pendingInvites[sender] = nil
            InviteTrade.clearTravelAnnouncement(sender)
            UI.updateTicketList()
            UI.updateTicketFrame()
            -- Tracking only. Use the ticket's Remove button to also drop them from the group.
            Utils.print("Stopped tracking " .. sender .. ". They are still in the party.")
        end
    elseif command == "destination" then
        local name, destination = rest:match("^(%S+)%s+(%S+)$")
        local sender, inviteData = findTicket(name)

        if not name or not destination then
            Utils.print("Usage: /Tp destination [player] [destination]")
        elseif not sender then
            Utils.print("No ticket found for '" .. name .. "'. Try /Tp list.")
        elseif not Utils.isUsableDestination(destination) then
            Utils.print("'" .. destination .. "' is not a destination this addon can resolve. Add it " ..
                            "under Destination Keywords in the options panel first.")
        else
            inviteData.destination = destination
            -- A deliberate choice, so later messages must not overwrite it.
            inviteData.destinationLocked = true

            local portal = Utils.getMatchingPortal(destination)

            UI.updateTicketFrame()
            Utils.print("Destination for " .. sender .. " set to " .. destination .. " -> " ..
                            (portal.matched and portal.locationName or "unresolved") .. " (locked).")
        end
    elseif command == "help" then
        Utils.print("Usage:")
        print("/Tp show - Show the addon button")
        print("/Tp on - Enable the addon")
        print("/Tp off - Disable the addon")
        print("/Tp msg [message] - Set the invite message")
        print("/Tp debug on/off - Enable or disable debug mode")
        print("/Tp checkspells - Check what conjure spells are detected")
        print("/Tp author - The creator")
        print("/Tp help - Show this help message")
        print("/Tp keywords add/remove intent/destination/service [keyword] - Add or remove a keyword")
        print("/Tp parse [message] - Explain how a request would be matched")
        print("/Tp list - List tracked tickets")
        print("/Tp add [player] [destination] - Track a customer the addon missed")
        print("/Tp remove [player] - Stop tracking a customer")
        print("/Tp destination [player] [destination] - Set and lock a ticket's destination")
        print("/Tp cooldown [seconds] - Set the invite cooldown period")
    elseif command == "author" then
        Utils.print("This addon was created by [Thic-Ashbringer EU].")
    else
        Utils.print("Invalid command. Type /Tp help for usage instructions.")
    end
end

-- Add slash command
SLASH_TP1 = "/Tp"

SlashCmdList["TP"] = function(msg)
    handleCommand(msg)
end

return ThicPortals
