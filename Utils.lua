-- Events.lua
local Config = _G.Config

-- Utils.lua
local Utils = {}

-- Function to calculate the distance between two points using the Pythagorean theorem
function Utils.calculateDistance(playerX, playerY, targetX, targetY)
    return math.sqrt((playerX - targetX) ^ 2 + (playerY - targetY) ^ 2)
end

-- Function to check if a value equals another value in a table
function Utils.keywordInTable(keyword, keywordList)
    keyword = keyword:lower()
    for _, phrase in ipairs(keywordList) do
        if keyword == phrase:lower() then
            return true
        end
    end
    return false
end

-- Helper function to escape Lua pattern special characters
local function escapePattern(text)
    return text:gsub("([^%w])", "%%%1")
end

-- Function to check if a message contains any exact keyword/phrase match.
function Utils.messageHasPhraseOrKeyword(message, keywordList)
    -- Pad the message with spaces at the beginning and end.
    message = " " .. message:lower() .. " "
    for _, phrase in ipairs(keywordList) do
        if phrase:sub(1, 1) == "%" and phrase:sub(-1) == "%" then
            -- Contains style search: remove the leading and trailing '%' characters.
            local substring = phrase:sub(2, -2):lower()
            if string.find(message, substring, 1, true) then
                return substring
            end
        else
            -- Use frontier patterns to ensure whole word/phrase matching.
            local escapedPhrase = escapePattern(phrase:lower())
            local pattern = "%f[%w]" .. escapedPhrase .. "%f[%W]"
            if string.find(message, pattern) then
                return phrase
            end
        end
    end
    return false
end

-- Function to find if a message contains any keyword from a list and return the position and matched keyword
function Utils.findKeywordPosition(message, keywordList)
    -- Pad the message with spaces at the beginning and end.
    message = " " .. message:lower() .. " "
    for _, keyword in ipairs(keywordList) do
        local pattern = "%f[%w]" .. keyword:lower() .. "%f[%W]"
        local position = string.find(message, pattern)
        if position then
            return position, keyword
        end
    end
    return nil, nil
end

-- Function to find every distinct keyword from a list that appears in a message, ordered by
-- where they appear rather than by their position in the keyword list.
--
-- Where two keywords overlap the longer one wins, so "thunder bluff" is reported once rather
-- than also matching the bare "thunder" sitting inside it. Each keyword is reported at most
-- once. Used to offer the user a choice when a request names more than one city, e.g.
-- "wtb port from sw to if" -> {"sw", "if"}.
function Utils.findAllKeywordPositions(message, keywordList)
    if not message or not keywordList then
        return {}
    end

    -- Pad the message with spaces at the beginning and end.
    local padded = " " .. message:lower() .. " "
    local hits = {}

    for _, keyword in ipairs(keywordList) do
        local pattern = "%f[%w]" .. escapePattern(keyword:lower()) .. "%f[%W]"
        local searchFrom = 1
        while true do
            local startPos, endPos = string.find(padded, pattern, searchFrom)
            if not startPos then
                break
            end
            table.insert(hits, {
                position = startPos,
                finish = endPos,
                keyword = keyword
            })
            searchFrom = startPos + 1
        end
    end

    -- Earliest match first; where two start at the same spot, prefer the longer keyword.
    table.sort(hits, function(a, b)
        if a.position ~= b.position then
            return a.position < b.position
        end
        return a.finish > b.finish
    end)

    local results = {}
    local seen = {}
    local consumedUpTo = 0

    for _, hit in ipairs(hits) do
        local normalizedKeyword = hit.keyword:lower()
        if hit.position > consumedUpTo and not seen[normalizedKeyword] then
            seen[normalizedKeyword] = true
            consumedUpTo = hit.finish
            table.insert(results, {
                position = hit.position,
                keyword = hit.keyword
            })
        end
    end

    return results
end

-- Words that mark the location straight after them as where the customer wants to GO.
local DESTINATION_MARKERS = {
    ["to"] = true,
    ["2"] = true,
    ["too"] = true,
    [">"] = true,
    [">>"] = true,
    ["->"] = true,
    ["=>"] = true
}

-- Words that mark the location straight after them as where the customer already IS.
local ORIGIN_MARKERS = {
    ["from"] = true,
    ["in"] = true,
    ["at"] = true,
    ["im"] = true,
    ["i'm"] = true
}

local function classifyPrecedingText(text)
    if not text then
        return 0
    end

    -- Arrows are often written without spaces ("sw->if"), so check them before extracting
    -- a word. A plain greater-than sign is also accepted for messages such as "sw > if".
    if text:match("%-%>%s*$") or text:match("=%>%s*$") or text:match(">>%s*$") or
        text:match(">%s*$") then
        return 1
    end

    -- Allow punctuation between the marker and location ("to: SW", "(from IF)").
    local word = text:match("([%w']+)[%p%s]*$")
    if DESTINATION_MARKERS[word] then
        return 1
    elseif ORIGIN_MARKERS[word] then
        return -1
    end

    return 0
end

-- Function to work out which location in a message the customer actually wants to travel to.
--
-- Returns the same (position, keyword) pair as findKeywordPosition, plus an originOnly flag,
-- and understands that "wtb port from sw to if" means Ironforge, not Stormwind.
-- The word immediately before each location decides: "to if" is a destination, "from sw" and
-- "in sw" are where they are standing. With nothing to go on it keeps the old behaviour and
-- takes the first location mentioned.
function Utils.findRequestedDestination(message, keywordList)
    if not message or not keywordList then
        return nil, nil, false
    end

    local candidates = Utils.findAllKeywordPositions(message, keywordList)

    if #candidates == 0 then
        return nil, nil, false
    end

    local padded = " " .. message:lower() .. " "
    local best = nil
    local bestScore = -2

    for _, candidate in ipairs(candidates) do
        local precedingText = padded:sub(1, candidate.position - 1)
        local score = classifyPrecedingText(precedingText)

        -- Take a better score, and among equally marked destinations take the later one,
        -- because "from A to B" puts the location they actually want last.
        if score > bestScore or (score == bestScore and score > 0) then
            bestScore = score
            best = candidate
        end
    end

    -- Callers matching a new request still need the best available city as a fallback: phrases
    -- such as "portal in Stormwind" commonly mean Stormwind is the requested destination.
    -- The third return lets follow-up handling avoid retargeting on an origin-only message.
    return best.position, best.keyword, bestScore < 0
end

-- Function to replace placeholders in messages with actual values
function Utils.replacePlaceholders(message, destination)
    if not message then
        return message
    end

    -- Replace %destination% with the actual destination
    if destination then
        message = string.gsub(message, "%%destination%%", destination)
    end

    return message
end

-- Function to update the distance label in the UI based on the distance between two players
-- Only one distance ticker may be live at a time. updateTicketFrame runs on every target change,
-- roster update and destination chip click, and the in-ticker guard below only fires when the
-- displayed sender *changes* - so refreshing the same ticket stacked tickers that never stopped,
-- all writing to the same label. Cancel the outgoing one before starting its replacement.
local distanceTicker

-- Stop the live distance ticker. Called when the ticket window is hidden or empties out: without
-- this the ticker keeps polling UnitPosition every second for a customer who is still grouped but
-- no longer on screen, because the in-ticker guards only fire on a sender change or a party leave.
function Utils.cancelDistanceTicker()
    if distanceTicker then
        distanceTicker:Cancel()
        distanceTicker = nil
    end
end

-- Cancel from inside the ticker itself. Only clears the stored reference when it still points at
-- this ticker; a newer one may already have replaced it.
local function stopDistanceTicker(ticker)
    ticker:Cancel()

    if distanceTicker == ticker then
        distanceTicker = nil
    end
end

function Utils.updateDistanceLabel(sender, distanceLabel)
    Utils.cancelDistanceTicker()

    local ticker

    local function refresh()
        -- Only update if the label is still for the correct sender
        if UI.ticketFrame and UI.ticketFrame.currentSender ~= sender then
            if ticker then
                stopDistanceTicker(ticker)
            end
            return
        end

        if UnitInParty(sender) then
            -- One owner for this line: it shows a distance while the customer is in the same zone
            -- and where they are when they are not, and the travel button follows the same call.
            UI.updateLocationLine(sender, distanceLabel)
        else
            distanceLabel:SetText("Distance: N/A")
            UI.hideTravelButton()

            if ticker then
                stopDistanceTicker(ticker) -- Cancel the ticker if the player is no longer in the party
            end
        end
    end

    -- Run once now: a ticket opening should not show a stale line for a second first.
    refresh()

    ticker = C_Timer.NewTicker(1, refresh)
    distanceTicker = ticker
end

-- Function to calculate the required height for text
function Utils.calculateTextHeight(fontString, text, width)
    fontString:SetWidth(width)
    fontString:SetText(text)
    fontString:SetWordWrap(true)
    local height = fontString:GetStringHeight()
    return height
end

-- Function to add tip to rolling total
function Utils.addTipToRollingTotal(gold, silver, copper)
    local totalCopper = gold * 10000 + silver * 100 + copper

    Config.Settings.totalGold = Config.Settings.totalGold + totalCopper
    Config.Settings.dailyGold = Config.Settings.dailyGold + totalCopper

    Utils.printGoldInformation()
end

-- Function to print gold information
function Utils.printGoldInformation()
    Utils.print(string.format("Total trades completed: %d", Config.Settings.totalTradesCompleted))
    Utils.print(string.format("Total gold earned: %dg %ds %dc",
        math.floor(Config.Settings.totalGold / 10000), math.floor((Config.Settings.totalGold % 10000) / 100),
        Config.Settings.totalGold % 100))
    Utils.print(string.format("Gold earned today: %dg %ds %dc",
        math.floor(Config.Settings.dailyGold / 10000), math.floor((Config.Settings.dailyGold % 10000) / 100),
        Config.Settings.dailyGold % 100))
end

-- Function to reset daily gold if needed
function Utils.resetDailyGoldIfNeeded()
    local currentDate = date("%Y-%m-%d")
    if Config.Settings.lastUpdateDate ~= currentDate then
        Config.Settings.dailyGold = 0
        Config.Settings.lastUpdateDate = currentDate
        Utils.print("Daily gold counter reset for a new day.")
    end
end

-- Function to increment trades completed
function Utils.incrementTradesCompleted()
    Config.Settings.totalTradesCompleted = Config.Settings.totalTradesCompleted + 1
end

-- Function to check if the player is within range using the UnitPosition API
function Utils.isPlayerWithinRange(sender, range)
    local playerX, playerY, playerInstanceID = UnitPosition("player")
    local targetX, targetY, targetInstanceID = UnitPosition(sender)

    if playerInstanceID == targetInstanceID then
        local distance = Utils.calculateDistance(playerX, playerY, targetX, targetY)
        return distance <= range -- Example threshold for being "travelled"
    end

    return false
end

-- Function to check if a player is on the ban list
function Utils.isPlayerBanned(player)
    for _, bannedPlayer in ipairs(Config.Settings.BanList) do
        if bannedPlayer == player then
            return true
        end
    end
    return false
end

-- Every shipped DestinationKeywords entry, mapped to the canonical city it means. Declared rather
-- than inferred: the old letter-frequency scoring sent "org" to Ironforge, "sm" and "ston" to
-- Stormwind, because it counted letters anywhere in the name, ignoring order and duplicates.
Utils.DestinationAliases = {
    ["darn"] = "Darnassus",
    ["darnassuss"] = "Darnassus",
    ["darnas"] = "Darnassus",
    ["darrna"] = "Darnassus",
    ["darnaas"] = "Darnassus",
    ["darnassus"] = "Darnassus",
    ["darnasuss"] = "Darnassus",
    ["darna"] = "Darnassus",
    ["darnasus"] = "Darnassus",
    --
    ["sw"] = "Stormwind",
    ["stormwind"] = "Stormwind",
    ["storm wind"] = "Stormwind",
    --
    ["if"] = "Ironforge",
    ["ironforge"] = "Ironforge",
    ["iron forge"] = "Ironforge",
    --
    ["exodar"] = "Exodar",
    ["exo"] = "Exodar",
    --
    ["theramore"] = "Theramore",
    ["thera"] = "Theramore",
    ["tmore"] = "Theramore",
    --
    ["org"] = "Orgrimmar",
    ["orgrimmar"] = "Orgrimmar",
    ["orgri"] = "Orgrimmar",
    ["orgim"] = "Orgrimmar",
    --
    ["tb"] = "Thunder Bluff",
    ["thunder bluff"] = "Thunder Bluff",
    ["thunderbluff"] = "Thunder Bluff",
    ["thunder"] = "Thunder Bluff",
    --
    ["uc"] = "Undercity",
    ["undercity"] = "Undercity",
    ["under city"] = "Undercity",
    --
    ["silvermoon"] = "Silvermoon",
    ["silver moon"] = "Silvermoon",
    ["sm"] = "Silvermoon",
    ["silv"] = "Silvermoon",
    --
    ["stonard"] = "Stonard",
    ["ston"] = "Stonard",
    --
    ["shattrath"] = "Shattrath",
    ["shatt"] = "Shattrath",
    ["shat"] = "Shattrath",
    ["shath"] = "Shattrath"
}

-- Canonical city -> the portal spell that goes there, replacing the old if/elseif chain.
-- Shattrath is the one destination both factions can reach, via different spells.
Utils.PortalSpells = {
    ["Darnassus"] = {
        spellID = 11419
    },
    ["Stormwind"] = {
        spellID = 10059
    },
    ["Ironforge"] = {
        spellID = 11416
    },
    ["Exodar"] = {
        spellID = 32266
    },
    ["Theramore"] = {
        spellID = 49360
    },
    ["Orgrimmar"] = {
        spellID = 11417
    },
    ["Thunder Bluff"] = {
        spellID = 11420
    },
    ["Undercity"] = {
        spellID = 11418
    },
    ["Silvermoon"] = {
        spellID = 32267
    },
    ["Stonard"] = {
        spellID = 49361
    },
    ["Shattrath"] = {
        byFaction = {
            Alliance = 33691,
            Horde = 35717
        }
    }
}

-- The canonical city a keyword names, or nil when it is not one we ship a mapping for. Custom
-- keywords added through the options panel fall through here and are resolved by the heuristic.
function Utils.resolveCanonicalDestination(destination)
    if not destination then
        return nil
    end

    return Utils.DestinationAliases[destination:lower()]
end

-- The original letter-frequency scoring, kept only as the fallback for user-added keywords that
-- the explicit map knows nothing about. Wrong for several shipped abbreviations, which is exactly
-- why the map exists - but removing it outright would break custom keywords that currently work.
function Utils.matchPortalByHeuristic(destination)
    local destinationLength = string.len(destination)
    local bestMatch = nil
    local maxMatches = 0

    for _, portalName in ipairs(Config.Portals) do
        local spellDestination = portalName:match("Portal: (.+)"):lower()
        local matches = 0

        for i = 1, destinationLength do
            if spellDestination:find(destination:sub(i, i), 1, true) then
                matches = matches + 1
            end
        end

        if matches > maxMatches then
            maxMatches = matches
            bestMatch = portalName
        end
    end

    if not bestMatch then
        return nil
    end

    return bestMatch:match("Portal: (.+)")
end

-- Resolve a destination keyword to the portal we should cast.
--
-- Explicit map first, heuristic only for keywords it does not cover. The returned shape is
-- unchanged: matched/spellID/spellName/locationName, plus canonical, which is set only when the
-- explicit map answered - callers use that to tell a known city from a guess.
function Utils.getMatchingPortal(destination)
    local portal = {
        matched = false,
        spellID = 10059,
        spellName = "Portal: Stormwind",
        locationName = "Stormwind",
        canonical = nil
    }

    if not destination then
        return portal
    end

    local canonical = Utils.resolveCanonicalDestination(destination)
    local resolvedByMap = canonical ~= nil

    if not canonical then
        canonical = Utils.matchPortalByHeuristic(destination)
    end

    if not canonical then
        return portal
    end

    local spell = Utils.PortalSpells[canonical]

    if not spell then
        return portal
    end

    local spellID = spell.spellID

    if not spellID and spell.byFaction then
        local englishFaction = UnitFactionGroup("player")
        spellID = spell.byFaction[englishFaction]
    end

    Utils.debugPrint("Destination \"" .. destination .. "\" resolved to " .. canonical ..
                         (resolvedByMap and " (alias map)" or " (heuristic fallback)"))

    return {
        matched = true,
        spellID = spellID,
        spellName = "Portal: " .. canonical,
        locationName = canonical,
        canonical = resolvedByMap and canonical or nil
    }
end

-- Collapse keywords that are aliases for the same city, so "port to if from sw, im in stormwind"
-- offers two chips rather than three. Only collapses when BOTH keywords resolve through the
-- explicit map: the heuristic is not trustworthy enough to merge on, and merging on it would hide
-- a real choice (it scores "org" and "if" identically, so they would become one chip).
function Utils.dedupeDestinationCandidates(candidates, selectedKeyword)
    local deduped = {}
    local seenCanonical = {}

    -- Which alias to keep for the selected destination's city. Keeping the first alias named would
    -- discard the selected one whenever it is not the first: "from stormwind to sw" with "sw"
    -- selected would keep "stormwind", and the selected destination would then be neither pinned
    -- nor shown in gold, because both are matched by keyword.
    local preferred, preferredCanonical

    if selectedKeyword then
        preferredCanonical = Utils.resolveCanonicalDestination(selectedKeyword)

        if preferredCanonical then
            for _, candidate in ipairs(candidates) do
                if candidate.keyword == selectedKeyword then
                    preferred = candidate
                    break
                end
            end
        end

        -- Selected keyword is not among the candidates: nothing to preserve.
        if not preferred then
            preferredCanonical = nil
        end
    end

    for _, candidate in ipairs(candidates) do
        local canonical = Utils.resolveCanonicalDestination(candidate.keyword)

        if not canonical then
            -- Unmapped/custom keyword: always kept, never merged with anything.
            deduped[#deduped + 1] = candidate
        elseif not seenCanonical[canonical] then
            seenCanonical[canonical] = true

            -- Hold the group's place in the message, but keep the selected alias's keyword.
            if canonical == preferredCanonical then
                deduped[#deduped + 1] = preferred
            else
                deduped[#deduped + 1] = candidate
            end
        end
    end

    return deduped
end
-- Convert the copper value to a gold, silver, and copper formatted string
function Utils.formatCopperValue(totalCost)
    local gold = math.floor(totalCost / 10000)
    local silver = math.floor((totalCost % 10000) / 100)
    local copper = totalCost % 100

    local formattedString = ""

    if gold > 0 then
        formattedString = string.format("%dg", gold)
    end

    if silver > 0 then
        if #formattedString > 0 then
            formattedString = formattedString .. " "
        end
        formattedString = formattedString .. string.format("%ds", silver)
    end

    if copper > 0 then
        if #formattedString > 0 then
            formattedString = formattedString .. " "
        end
        formattedString = formattedString .. string.format("%dc", copper)
    end

    return formattedString
end

-- Function to check if a spell rank is known by the player
-- Find the party unit token for a customer we track by name.
--
-- Tickets are keyed by player name, and UnitInParty happily accepts a name - but the C_Map calls
-- want a real unit token, and quietly return nothing for a name. Resolve once, here, and keep the
-- name purely for display.
function Utils.getPartyUnitToken(name)
    if not name or name == "" then
        return nil
    end

    -- Tickets may carry either "Player" or "Player-Realm".
    local wantedName, wantedRealm = name:match("^([^%-]+)%-?(.*)$")

    if not wantedName then
        return nil
    end

    wantedName = wantedName:lower()

    if wantedRealm == "" then
        wantedRealm = nil
    else
        wantedRealm = wantedRealm:gsub("%s+", ""):lower()
    end

    for index = 1, (MAX_PARTY_MEMBERS or 4) do
        local token = "party" .. index

        if UnitExists(token) then
            local unitName, unitRealm = UnitName(token)

            if unitName and unitName:lower() == wantedName then
                if not wantedRealm then
                    -- Bare-name ticket: the name alone decides, as before.
                    return token
                end

                -- The ticket named a realm, so it has to match. UnitName reports an empty realm
                -- for units on our own realm rather than naming it, so resolve that to the
                -- player's realm instead of treating it as a wildcard - accepting a blank would
                -- match a same-realm namesake of a cross-realm customer.
                local effectiveRealm = unitRealm

                if not effectiveRealm or effectiveRealm == "" then
                    effectiveRealm = GetRealmName and GetRealmName() or nil
                end

                -- Realm suffixes carry no spaces ("Thunder Bluff" -> "ThunderBluff").
                if effectiveRealm and effectiveRealm:gsub("%s+", ""):lower() == wantedRealm then
                    return token
                end
            end
        end
    end

    return nil
end

-- The zone a unit is standing in, or nil when the client will not tell us. Takes a unit token, not
-- a name - see Utils.getPartyUnitToken.
function Utils.getUnitZoneName(unit)
    if not unit or not C_Map or not C_Map.GetBestMapForUnit then
        return nil
    end

    local mapID = C_Map.GetBestMapForUnit(unit)

    if not mapID then
        return nil
    end

    local mapInfo = C_Map.GetMapInfo(mapID)

    return mapInfo and mapInfo.name or nil
end

-- Which canonical city a zone name refers to, or nil when it is not one we can travel to.
-- Matched by name against the same canonical cities the portal map uses, so it needs no table of
-- map IDs - those differ between the Classic Era and TBC clients this addon both supports.
-- "Stormwind City" -> Stormwind, "The Exodar" -> Exodar, "Silvermoon City" -> Silvermoon.
function Utils.resolveCityFromZoneName(zoneName)
    if not zoneName then
        return nil
    end

    local normalized = zoneName:lower()
    local best = nil

    for city in pairs(Utils.PortalSpells) do
        -- Longest match wins so a hypothetical overlap cannot pick the shorter city.
        if normalized:find(city:lower(), 1, true) and (not best or #city > #best) then
            best = city
        end
    end

    return best
end

-- Whether the player's spellbook contains a spell with this exact name, ignoring rank. Used to ask
-- "can this mage actually teleport there", which also settles faction and level with no extra
-- logic: a Horde mage simply has no Teleport: Stormwind.
function Utils.isSpellKnownByName(spellName)
    if not spellName then
        return false
    end

    local i = 1

    while i <= 1024 do
        local knownName = GetSpellBookItemName(i, BOOKTYPE_SPELL)

        if not knownName then
            break
        end

        if knownName == spellName then
            return true
        end

        i = i + 1
    end

    return false
end

-- The self-teleport for a canonical city, but only if the mage knows it. Every "Portal: X" has a
-- matching "Teleport: X", so the name is derived rather than stored.
function Utils.getKnownTeleportSpell(city)
    if not city or not Utils.PortalSpells[city] then
        return nil
    end

    local spellName = "Teleport: " .. city

    if not Utils.isSpellKnownByName(spellName) then
        return nil
    end

    return spellName
end

function Utils.isSpellRankKnown(spellBaseName, rank)
    if not spellBaseName or not rank then
        return false
    end

    -- In Classic, we need to iterate through all spell slots
    local i = 1
    local maxSpells = 1024 -- Safe upper limit

    while i <= maxSpells do
        local spellName, spellSubName = GetSpellBookItemName(i, BOOKTYPE_SPELL)

        if not spellName then
            break
        end

        -- Check if the spell name matches what we're looking for
        if spellName == spellBaseName then
            -- spellSubName contains rank info like "Rank 7"
            if spellSubName then
                local rankNum = tonumber(spellSubName:match("(%d+)"))
                if rankNum and rankNum >= rank then
                    -- If the player knows this rank or higher, they can conjure this item
                    return true
                end
            elseif not spellSubName and rank == 1 then
                -- Some spells don't have ranks, treat as rank 1
                return true
            end
        end

        i = i + 1
    end

    return false
end

-- Function to get available food items (that the mage can conjure)
function Utils.getAvailableFoodItems()
    local availableItems = {}
    for _, item in ipairs(Config.Settings.foodItems or {}) do
        if Utils.isSpellRankKnown(item.spellName, item.rank) then
            table.insert(availableItems, item)
        end
    end
    return availableItems
end

-- Function to get available water items (that the mage can conjure)
function Utils.getAvailableWaterItems()
    local availableItems = {}
    for _, item in ipairs(Config.Settings.waterItems or {}) do
        if Utils.isSpellRankKnown(item.spellName, item.rank) then
            table.insert(availableItems, item)
        end
    end
    return availableItems
end

-- Function to get the highest tier food item the player has in inventory
function Utils.getHighestTierFoodInInventory()
    local availableFood = Utils.getAvailableFoodItems()
    -- Iterate in reverse order (highest tier first)
    for i = #availableFood, 1, -1 do
        local item = availableFood[i]
        local count = GetItemCount(item.itemId, false)
        if count > 0 then
            return item, count
        end
    end
    return nil, 0
end

-- Function to get the highest tier water item the player has in inventory
function Utils.getHighestTierWaterInInventory()
    local availableWater = Utils.getAvailableWaterItems()
    -- Iterate in reverse order (highest tier first)
    for i = #availableWater, 1, -1 do
        local item = availableWater[i]
        local count = GetItemCount(item.itemId, false)
        if count > 0 then
            return item, count
        end
    end
    return nil, 0
end

function Utils.print(message)
    print("|cff87CEEB[Thic-Portals]|r " .. message)
end

function Utils.debugPrint(message)
    if Config.Settings.debugMode then
        Utils.print(message)
    end
end

_G.Utils = Utils

return Utils
