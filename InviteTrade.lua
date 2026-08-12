-- InviteTrade.lua
local Config = _G.Config
local Utils = _G.Utils

local InviteTrade = {}

-- Function to play a sound when a match is found
local function playMatchSound()
    if Config.Settings.soundEnabled then
        PlaySoundFile("Interface\\AddOns\\ThicPortals\\Media\\Sounds\\invitesent.mp3", "Master")
    end
end

-- Function to match food and water requests
local function matchFoodAndWaterRequests(message)
    local isFoodRequested = false
    local isWaterRequested = false

    for foodKeyword in Config.Settings.FoodKeywords do
        if string.find(message:lower(), foodKeyword:lower()) then
            isFoodRequested = true
        end
    end

    for waterKeyword in Config.Settings.WaterKeywords do
        if string.find(message:lower(), waterKeyword:lower()) then
            isWaterRequested = true
        end
    end

    return isFoodRequested, isWaterRequested
end

-- Function to check if a player can be invited (based on cooldown)
local function stillOnCooldown(playerName)
    -- If the player is in the pending invites table and has not joined and the cooldown hasn't expired
    return Events.pendingInvites[playerName] and not Events.pendingInvites[playerName].hasJoined and
               (time() - Events.pendingInvites[playerName].timestamp) < Config.Settings.inviteCooldown
end

-- Function to update the destination of a pending invite
local function updatePendingInviteDestination(playerName, message)
    -- A destination the user picked by hand on the ticket outranks anything we infer from a
    -- later message, otherwise a follow-up like "thanks, im in sw" silently retargets the ticket.
    if Events.pendingInvites[playerName] and Events.pendingInvites[playerName].destinationLocked then
        Utils.debugPrint("Destination for " .. playerName .. " was set manually - not overwriting.")
        return
    end

    local destinationPosition, destinationKeyword, originOnly = Utils.findRequestedDestination(message,
        Config.Settings.DestinationKeywords)
    if originOnly then
        Utils.debugPrint("Message from " .. playerName ..
            " only identifies their current location - not overwriting destination.")
        return
    end

    if destinationPosition and Events.pendingInvites[playerName] then
        Events.pendingInvites[playerName].destination = destinationKeyword

        if Events.pendingInvites[playerName].destinationValue then
            Events.pendingInvites[playerName].destinationValue:SetText(destinationKeyword)
        end

        Utils.print("Updated destination for " .. playerName .. " to " .. destinationKeyword)

        if Events.pendingInvites[playerName].actionButton then
            -- Set the icon texture for the portal spell
            UI.setIconSpell(Events.pendingInvites[playerName], Events.pendingInvites[playerName].destination)
        end
    end
end

-- Function to handle sending an invite to a player
function InviteTrade.invitePlayer(sender)
    if Config.Settings.removeRealmFromInviteCommand then
        -- sender = Thicfury-Ashbringer for example, we want to remove the realm part
        sender = string.match(sender, "([^%-]+)")
    end

    -- Use the appropriate invite function based on the WoW version
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(sender)
    else
        InviteUnit(sender)
    end

    playMatchSound()

    Utils.print("Invited " .. sender .. " to the group.")
end

-- Function to create a pending invite entry
function InviteTrade.createPendingInvite(playerName, playerClass, sender, message, destinationKeyword)
    Events.pendingInvites[playerName] = {
        timestamp = time(),
        class = playerClass,
        name = playerName,
        fullName = sender,
        destination = destinationKeyword,
        originalMessage = message,
        hasJoined = false,
        hasPaid = false,
        travelled = false
    }

    InviteTrade.setSenderExpiryTimer(playerName)
end

-- Function to handle invite and message for common phrases
function InviteTrade.handleCommonPhraseInvite(message)
    local phrase = Utils.messageHasPhraseOrKeyword(message, Config.Settings.commonPhrases)
    local destinationPosition, destinationKeyword = Utils.findRequestedDestination(message,
        Config.Settings.DestinationKeywords)

    if phrase then
        Utils.debugPrint("[Common-phrase-invite] Matched on common phrase: " .. phrase)
        Utils.debugPrint("[Common-phrase-invite] Destination keyword: " ..
                    (destinationKeyword or "none"))
    else
        Utils.debugPrint("[Common-phrase-invite] Failed to match via common phrase")
    end

    return phrase, destinationKeyword
end

-- Function to handle invites with destination keywords
function InviteTrade.handleDestinationOnlyInvite(message)
    local destinationPosition, destinationKeyword = Utils.findRequestedDestination(message,
        Config.Settings.DestinationKeywords)

    if destinationPosition then
        Utils.debugPrint("[Destination-only-invite] Matched on destination keyword: " ..
                    destinationKeyword)
    else
        Utils.debugPrint("[Destination-only-invite] Failed to match via destination keyword")
    end

    local matched = destinationPosition and true or false

    return matched, destinationKeyword
end

-- Function to handle advanced keyword detection invites
function InviteTrade.handleAdvancedKeywordInvite(message)
    local matched = false
    local destinationKeyword = nil

    local intentPosition, intentKeyword = Utils.findKeywordPosition(message, Config.Settings.IntentKeywords)
    if intentPosition then
        Utils.debugPrint("[Advanced-keyword-invite] Matched on intent keyword: " .. intentKeyword ..
                    " (position: " .. intentPosition .. ")")

        local servicePosition, serviceKeyword = Utils.findKeywordPosition(message, Config.Settings.ServiceKeywords)
        local destinationPosition, destKeyword = Utils.findRequestedDestination(message, Config.Settings.DestinationKeywords)

        if servicePosition and servicePosition > intentPosition then
            matched = true
            destinationKeyword = destKeyword

            Utils.debugPrint("[Advanced-keyword-invite] Matched on service keyword: " ..
                        serviceKeyword .. " (position: " .. servicePosition .. ")")

            if destinationPosition then
                Utils.debugPrint("[Advanced-keyword-invite] Matched on destination keyword: " ..
                            destKeyword .. " (position: " .. destinationPosition .. ")")
            else
                Utils.debugPrint("[Advanced-keyword-invite] Failed to match via advanced keyword matching - no destination keyword found.")
            end
        else
            Utils.debugPrint("[Advanced-keyword-invite] Failed to match via advanced keyword matching - no service keyword found.")
        end
    else
        Utils.debugPrint("[Advanced-keyword-invite] Failed to match via advanced keyword matching - no intent keyword found.")
    end

    return matched, destinationKeyword
end

-- Main function to handle invites and messages
function InviteTrade.handleInviteAndMessage(sender, playerName, playerClass, message, destinationOnly)
    -- Check if we've reached the maximum number of simultaneous tickets
    local currentTicketCount = 0
    for _, inviteData in pairs(Events.pendingInvites) do
        if inviteData.hasJoined then
            currentTicketCount = currentTicketCount + 1
        end
    end

    if currentTicketCount >= Config.Settings.maxSimultaneousTickets then
        Utils.debugPrint("Maximum simultaneous tickets (" .. Config.Settings.maxSimultaneousTickets ..
                    ") reached. Ignoring invite for: " .. playerName)
        return
    end

    -- Here we deal with the player ban list
    if Utils.isPlayerBanned(sender) then
        Utils.debugPrint("Player " .. sender .. " is on the ban list. No invite sent.")
        return
    end

    -- Here we deal with the keyword ban list
    if Utils.messageHasPhraseOrKeyword(message, Config.Settings.KeywordBanList) then
        Utils.debugPrint("Player " .. sender .. " used a banned keyword. No invite sent.")
        return
    end

    -- Here we deal with potential invite cooldowns, this should only return early if the player hasn't joined yet
    if stillOnCooldown(playerName) then
        Utils.print("Player " .. sender .. " is still on invite cooldown.")
        return
    end

    -- Here we do our message matching
    local matched, destinationKeyword = InviteTrade.handleCommonPhraseInvite(message)

    if not Config.Settings.disableSmartMatching and not matched then
        if destinationOnly then
            matched, destinationKeyword = InviteTrade.handleDestinationOnlyInvite(message)
        else
            matched, destinationKeyword = InviteTrade.handleAdvancedKeywordInvite(message)
        end
    end

    if matched then
        if Config.Settings.requireDestination and not destinationKeyword then
            Utils.debugPrint("Invite match found from " .. playerName ..
                        ", but no (valid) destination keyword detected and Require Destination is enabled. Not sending invite.")
            return
        end
        InviteTrade.invitePlayer(sender)
        InviteTrade.createPendingInvite(playerName, playerClass, sender, message, destinationKeyword)
    end

    -- Update pending invite destination if a destination keyword is found in the new message
    updatePendingInviteDestination(playerName, message)
end

-- Travel announcement: "on my way" whispered to the one customer whose travel button was used.
--
-- Scoped to a click rather than to the spell, because a mage teleports for their own reasons all
-- the time - a manual cast from the spellbook must not whisper anybody. The click only records
-- intent; the whisper waits for the cast to actually begin, so a click that silently does nothing
-- promises nothing. It is sent at the START of the cast, not on completion: a teleport takes
-- around ten seconds, and that wait is exactly when a customer gives up and leaves the group.
InviteTrade.pendingTravelAnnouncement = nil

-- How long an armed intent stays usable. The cast begins within a frame or two of the click, so
-- this only has to outlive that gap - and keeping it short is what stops a click that never became
-- a cast (moving, silenced, out of range) from being consumed by a manual teleport later on.
local TRAVEL_ANNOUNCEMENT_WINDOW = 2

-- Each arming gets its own token, so a cleared-and-rearmed intent can never be mistaken for the
-- earlier one by a late event.
local travelAnnouncementToken = 0

function InviteTrade.beginTravelAnnouncement(sender, inviteData, city, spellName)
    travelAnnouncementToken = travelAnnouncementToken + 1

    InviteTrade.pendingTravelAnnouncement = {
        token = travelAnnouncementToken,
        armedAt = GetTime(),
        sender = sender,
        inviteData = inviteData,
        fullName = inviteData and inviteData.fullName,
        destination = inviteData and inviteData.destination,
        city = city,
        spellName = spellName,
        announced = false
    }

    -- Expire actively rather than waiting for some later event to notice. Without this the record
    -- simply sits there after a click that never cast; the token is what keeps this timer from
    -- clearing an intent armed after it.
    local token = travelAnnouncementToken

    C_Timer.After(TRAVEL_ANNOUNCEMENT_WINDOW, function()
        InviteTrade.clearTravelAnnouncement(nil, nil, token)
    end)

    return travelAnnouncementToken
end

-- Forget the pending announcement. Called when the cast ends however it ended, and whenever the
-- ticket it belongs to is replaced or removed.
--
-- Every filter is optional but exact when supplied: a spell failing mid-teleport is usually some
-- other spell entirely, and cancelling this intent because an unrelated cast failed would lose the
-- announcement for a teleport that is still perfectly on its way.
function InviteTrade.clearTravelAnnouncement(sender, spellName, token)
    local pending = InviteTrade.pendingTravelAnnouncement

    if not pending then
        return false
    end

    if sender and pending.sender ~= sender then
        return false
    end

    if spellName and pending.spellName ~= spellName then
        return false
    end

    if token and pending.token ~= token then
        return false
    end

    InviteTrade.pendingTravelAnnouncement = nil

    return true
end

-- Whisper the customer this teleport was started for. Returns whether anything was sent, which is
-- what the tests assert on.
function InviteTrade.announceTravelStart(spellName)
    local pending = InviteTrade.pendingTravelAnnouncement

    -- Nothing pending: a teleport the mage cast for their own reasons.
    if not pending or pending.announced then
        return false
    end

    -- A different teleport than the one the button was clicked for.
    if not spellName or pending.spellName ~= spellName then
        return false
    end

    -- Armed, but no cast followed. Drop it rather than let a later teleport inherit the intent.
    if GetTime() - pending.armedAt > TRAVEL_ANNOUNCEMENT_WINDOW then
        InviteTrade.pendingTravelAnnouncement = nil
        Utils.debugPrint("Travel announcement for " .. pending.sender .. " expired without a cast.")
        return false
    end

    -- The ticket may have been removed, or the customer may have left, during the click.
    if Events.pendingInvites[pending.sender] ~= pending.inviteData then
        InviteTrade.pendingTravelAnnouncement = nil
        return false
    end

    local template = Config.Settings.travelMessage

    if not template or template == "" then
        return false
    end

    pending.announced = true

    SendChatMessage(Utils.replacePlaceholders(template, pending.destination, pending.city), "WHISPER", nil,
        pending.fullName)

    Utils.debugPrint("Told " .. pending.sender .. " we are teleporting to " .. pending.city .. ".")

    return true
end

-- Explain what the matcher makes of a message, for /Tp parse.
--
-- Calls the same matching helpers the live path uses rather than reimplementing them, so the
-- explanation cannot drift from the behaviour it is describing. Pure with respect to the message:
-- it reads settings and touches no ticket state.
function InviteTrade.describeMatch(message)
    local keywords = Config.Settings.DestinationKeywords

    local commonPhrase = Utils.messageHasPhraseOrKeyword(message, Config.Settings.commonPhrases)
    local intentPosition, intentKeyword = Utils.findKeywordPosition(message, Config.Settings.IntentKeywords)
    local servicePosition, serviceKeyword = Utils.findKeywordPosition(message, Config.Settings.ServiceKeywords)

    local candidates = {}

    for _, candidate in ipairs(Utils.findAllKeywordPositions(message, keywords)) do
        candidates[#candidates + 1] = {
            keyword = candidate.keyword,
            marker = Utils.markerForPosition(message, candidate.position),
            canonical = Utils.resolveCanonicalDestination(candidate.keyword)
        }
    end

    local deduped = {}

    for _, candidate in ipairs(Utils.dedupeDestinationCandidates(Utils.findAllKeywordPositions(message, keywords))) do
        deduped[#deduped + 1] = candidate.keyword
    end

    local position, decision, originOnly = Utils.findRequestedDestination(message, keywords)
    local portal = decision and Utils.getMatchingPortal(decision) or nil

    -- Mirrors handleInviteAndMessage: common phrase first, then the intent-before-service rule.
    local advancedMatch = intentPosition and servicePosition and servicePosition > intentPosition
    local matched = (commonPhrase and true or false) or
                        (not Config.Settings.disableSmartMatching and advancedMatch and true or false)
    local blocked = nil

    if matched and Config.Settings.requireDestination and not decision then
        blocked = "Require Destination is on and no destination was found"
    end

    if Utils.messageHasPhraseOrKeyword(message, Config.Settings.KeywordBanList) then
        blocked = "message contains a banned keyword"
    end

    return {
        message = message,
        commonPhrase = commonPhrase or nil,
        intentKeyword = intentKeyword,
        intentPosition = intentPosition,
        serviceKeyword = serviceKeyword,
        servicePosition = servicePosition,
        candidates = candidates,
        deduped = deduped,
        decision = decision,
        decisionPosition = position,
        originOnly = originOnly,
        portal = portal,
        matched = matched,
        blocked = blocked,
        wouldInvite = matched and not blocked
    }
end

-- Function to set an expiry timer for pending invites
function InviteTrade.setSenderExpiryTimer(playerName)
    C_Timer.After(180, function()
        if Events.pendingInvites[playerName] then
            Utils.print("Invite for " .. playerName .. " expired.")
            Events.pendingInvites[playerName] = nil
        end
    end)
end

-- Function to mark yourself with a star when someone accepts the party invite
function InviteTrade.markSelfWithStar()
    SetRaidTarget("player", 1) -- 1 corresponds to the star raid marker
end

-- Function to watch for player's proximity to infer teleportation
function InviteTrade.watchForPlayerProximity(sender)
    local ticker
    local flagProximityReached = false

    ticker = C_Timer.NewTicker(1, function()
        if UnitInParty(sender) then
            if Utils.isPlayerWithinRange(sender, Config.Settings.distanceInferringClose) then
                if not flagProximityReached then
                    Utils.print(sender .. " is nearby and might be taking the portal.")
                    flagProximityReached = true
                end
            elseif flagProximityReached and
                not Utils.isPlayerWithinRange(sender, Config.Settings.distanceInferringTravelled) then
                Utils.debugPrint(sender .. " has moved away, assuming they took the portal.")

                if Events.pendingInvites[sender] then
                    Events.pendingInvites[sender].travelled = true
                end
                ticker:Cancel() -- Cancel the ticker when the player has moved away
            end
        else
            if Events.pendingInvites[sender] and Events.pendingInvites[sender].ticketFrame then
                Events.pendingInvites[sender].ticketFrame:Hide()
            end
            Events.pendingInvites[sender] = nil
            ticker:Cancel() -- Cancel the ticker if the player is no longer in the party
        end
    end)
end

-- Function to check if there was a tip in the trade
function InviteTrade.checkTradeTip()
    Utils.print("Checking trade tip...");

    local copper = tonumber(Config.currentTraderMoney);
    local silver = math.floor((copper % 10000) / 100);
    local gold = math.floor(copper / 10000);
    local remainingCopper = copper % 100;

    Utils.print(string.format("Received %dg %ds %dc from the trade.", gold, silver, remainingCopper));

    if gold > 0 or silver > 0 or remainingCopper > 0 then
        Utils.incrementTradesCompleted();
        Utils.resetDailyGoldIfNeeded();
        Utils.addTipToRollingTotal(gold, silver, remainingCopper);

        -- If the gold amount is higher than 8g, send a custom message via whisper saying "<3"
        if gold > 8 then
            SendChatMessage("<3", "WHISPER", nil, Events.pendingInvites[Config.currentTraderName].fullName)

            -- Send an emote "thank" to the player after they have accepted the trade
            DoEmote("thank", Config.currentTraderName)
        end

        -- If the gold amount is higher than 8g, send a custom message via whisper saying "<3"
        if gold == 69 or silver == 69 or remainingCopper == 69 then
            SendChatMessage("Nice (⌐□_□)", "WHISPER", nil,
                Events.pendingInvites[Config.currentTraderName].fullName)

            -- Send an emote "flirt" to the player after they sent a 69 tip
            DoEmote("flirt", Config.currentTraderName)
        end

        -- If the gold amount is higher than 8g, send a custom message via whisper saying "<3"
        if gold == 4 and silver == 20 then
            SendChatMessage("420 blaze it (⌐□_□)-~", "WHISPER", nil,
                Events.pendingInvites[Config.currentTraderName].fullName)

            -- Send an emote "silly" to the player after they sent a 420 tip
            DoEmote("silly", Config.currentTraderName)
        end

        return true
    else
        return false
    end
end

-- Function to also send mana users a message with water and food stockpiles and none mana users food stock
function InviteTrade.sendFoodAndWaterStockMessage(playerName, playerClass)
    -- Use the new smart detection to get the highest tier items in inventory
    local foodItem, foodCount = Utils.getHighestTierFoodInInventory()
    local waterItem, waterCount = Utils.getHighestTierWaterInInventory()

    local foodStock = nil
    local waterStock = nil

    -- Build food stock message if food is available
    if foodItem and foodCount > 0 then
        foodStock = foodCount .. " x " .. foodItem.name .. " (20x: " .. Utils.formatCopperValue(foodItem.price * 20) ..
                        ")"
    end

    -- Build water stock message if water is available
    if waterItem and waterCount > 0 then
        waterStock =
            waterCount .. " x " .. waterItem.name .. " (20x: " .. Utils.formatCopperValue(waterItem.price * 20) .. ")"
    end

    -- If the player has no food or water in their inventory, we will not advertise it
    if not foodStock and not waterStock then
        -- Print a warning to the player that they're out of stock
        Utils.print("You have run out of food and water stock. Please restock or disable food and water support.")
        return
    end

    local targetIsManaUser = false

    -- depending on the class of the player, we will advertise water or not
    if playerClass == "MAGE" or playerClass == "PRIEST" or playerClass == "WARLOCK" or playerClass == "DRUID" or
        playerClass == "SHAMAN" or playerClass == "PALADIN" then
        targetIsManaUser = true
    end

    -- if debug mode log both food and water stock
    Utils.debugPrint("Food stock: " .. (foodStock or "none"))
    Utils.debugPrint("Water stock: " .. (waterStock or "none"))

    if targetIsManaUser then
        if waterStock and foodStock then
            SendChatMessage(
                "I have " .. waterStock .. " and " .. foodStock .. " in stock if you require it - just ask!", "WHISPER",
                nil, playerName)
        elseif waterStock or foodStock then
            local stock = waterStock or foodStock
            SendChatMessage("I have " .. stock .. " in stock if you require it - just ask!", "WHISPER", nil, playerName)
        end
    elseif foodStock then
        SendChatMessage("I have " .. foodStock .. " in stock if you require it - just ask!", "WHISPER", nil, playerName)
    end
end

_G.InviteTrade = InviteTrade

return InviteTrade
