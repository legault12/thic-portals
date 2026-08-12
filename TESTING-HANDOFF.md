# Thic-Portals — working notes

Context for continuing this work. Rewritten 2026-08-11 after a full in-client session on the
gaming PC; supersedes the earlier Mac-era version of this document entirely.

**Status: ten commits on `test/ticket-destination`, six of them from the in-client session and
none of them pushed.** `origin/test/ticket-destination` still points at `2d13454`. No pull request
has been opened anywhere. Everything below the combat section has been exercised against a live
TBC Anniversary client during a real portal-selling session.

---

## 1. What this is

[Thic-Portals](https://github.com/MattGarnettWelsh/thic-portals) is a mage portal-service addon for
WoW Classic. It watches chat for portal requests, auto-invites the customer, and shows a "ticket"
with a button that casts the portal.

Upstream is `MattGarnettWelsh/thic-portals`, default branch `master`, addon version 3.4.2, last
pushed 2026-04-07 and quiet since. Two PRs (#12, #14) from `jdorsman` have sat open and unanswered
since April. Maintainer contact: Thic-Ashbringer (EU) in-game, or Discord
`https://discord.gg/RjfDtUmH`.

The fork is `legault12/thic-portals`, created 2026-08-11, public.

---

## 2. Commit stack

```
master (7cdc9a8, = upstream/master)
 └─ 46ccf28  Show the customer's original request on the ticket
     └─ c570dd8  Pick the destination after "to", not the first city mentioned
         └─ 5a15e2d  Address destination ticket review findings
             └─ 2d13454  Add testing handoff notes            ← origin/test/ticket-destination
                 └─ 3da5d2d  Fix ticket window anchoring, chip packing and the distance ticker leak
                     └─ 2454625  Resolve portal destinations from an explicit alias map
                         └─ 4e59127  Fix option tooltip erroring on every checkbox hover
                             └─ e03b10c  Show where a customer is, and offer a teleport to them
                                 └─ 16e67c2  Stop offering the city a customer is already standing in
                                     └─ 5644bcb  Whisper the customer when setting off to collect them
```

2,790 insertions / 241 deletions across 10 files versus upstream, including 937 lines of tests.

Commits are authored solely as `Marcus LeGault <legault12@gmail.com>`. Assistant attribution is
disabled machine-wide in `~/.claude/settings.json` (`attribution.commit`/`pr` empty,
`includeCoAuthoredBy: false`); keep it that way.

The only uncommitted change is `## Version: 3.4.2-test` in `ThicPortals.toc`, a deliberate marker
so the in-game addon list confirms which build loaded. Revert it before any PR.

---

## 3. Verified in-client

All of this was exercised on the live client, most of it during an actual selling session:

- From/to parsing: `wtb port from sw to if` resolves to Ironforge, confirmed with the real keyword
  list via `Utils.findRequestedDestination`
- Origin-worded requests (`wtb portal in sw`) still generate an invite — the §5 regression stayed
  fixed
- The ticket window builds without error, after the anchoring fix below
- Request text renders quoted and truncated on the ticket
- Destination chips render, size to their text, pack left to right, and cap at four
- Clicking a chip retargets the **protected** action button with no combat error; a second click
  locks the destination
- The `+N` overflow chip opens a list of the omitted destinations and picking one selects it
- `org` casts an Orgrimmar portal (it used to cast Ironforge)
- Alias collapse: `port to if from sw, im in stormwind` offers two chips, not three
- The location line shows `In: <zone>` for a customer elsewhere, and yard distance in-zone
- The travel button appears only for a known teleport and casts the right spell
- Paging between tickets replaces or clears the travel action correctly
- The travel whisper fires as the cast bar appears; a manual teleport whispers nobody
- Option checkbox tooltips no longer throw

---

## 4. What was fixed, and why it mattered

Grouped by commit. Four of these were only ever findable by running the addon.

### Ticket window anchoring (`3da5d2d`)

A `SecureActionButtonTemplate` is protected and **its entire anchor family must be frames**. The
portal button was anchored to `requestText`, a FontString, so building the ticket window raised
*"Cannot anchor protected frames to regions"* and the first real customer hit it. The text block
above is FontString-to-FontString throughout, so there is no legal route through it — the button is
pinned to the ticket frame instead.

**This is a standing constraint.** Nothing protected can hang off the ticket's text block, directly
or transitively. The first attempted fix anchored to `requestHitBox`, which is a Frame but is itself
`SetAllPoints(requestText)` — still illegal, because the whole chain is validated.

### Chip packing (`3da5d2d`)

Chips divided a fixed 180px row evenly, which clipped `stormwind` to `stormwi...` at three
candidates and left 16px each at nine. Now sized to their own text, packed left to right, capped at
four. A candidate that does not fit is skipped rather than ending the pack, the selected
destination is packed first so it is never the one dropped, and the first chip is clamped to the row
width so an oversized custom keyword cannot push the overflow indicator outside the frame.

### Distance ticker leak (`3da5d2d`)

`updateDistanceLabel` span a new one-second ticker per call and only self-cancelled when the
displayed sender *changed*, so refreshing the same ticket stacked tickers that never stopped — and a
chip click refreshes. One live ticker now, plus `Utils.cancelDistanceTicker` for the cases the
in-ticker guards cannot see, called on window hide and when the list empties.

### Portal matcher (`2454625`)

`getMatchingPortal` scored portals by counting how many letters of the request appeared *anywhere*
in the city name — ignoring order, double-counting duplicates, breaking ties by position in
`Config.Portals`. Four of the 41 shipped keywords resolved wrongly:

| keyword | wanted | got |
|---|---|---|
| `org`, `orgri` | Orgrimmar | Ironforge |
| `sm` | Silvermoon | Stormwind |
| `ston` | Stonard | Stormwind |

Replaced with two declared tables — alias → canonical city, canonical city → spell data, Shattrath
keeping its per-faction split. `DestinationKeywords` is user-editable, so the old heuristic survives
in `Utils.matchPortalByHeuristic` as the isolated fallback for keywords the map does not cover.
`getMatchingPortal` returns `canonical` only when the explicit map answered, which is what makes
chip deduplication safe: deduping on the heuristic would have merged `if` and `org` (it scores them
identically) and removed Orgrimmar as an option entirely.

### Option tooltip (`4e59127`)

`GameTooltip:SetText` takes `(text, r, g, b, alpha, wrap)`; `AddLine`'s wrap flag is its fifth
argument, `SetText`'s is its sixth. Upstream passed the boolean where alpha belongs, throwing on
every checkbox hover. **This bug is upstream's**, untouched by anything else here, and is the
cleanest standalone PR candidate in the stack.

### Location and travel (`e03b10c`)

The ticket now names the customer's zone when they are elsewhere, with a small teleport button
beside it. Notable pieces:

- No new spell or map tables. Every `Portal: X` has a matching `Teleport: X` and casting goes
  through `SetAttribute` by *name*, so the teleport is derived from the canonical city. Zones
  resolve by matching the map name against those same canonical names, avoiding map-ID tables that
  differ between the Classic Era and TBC clients the `.toc` supports.
- Tickets are keyed by player name; `C_Map` wants a unit token. `Utils.getPartyUnitToken` walks the
  party roster. A realm-qualified ticket must match on realm, and because `UnitName` reports a blank
  realm for our own, that resolves through `GetRealmName` rather than being treated as a wildcard.
- **Deferred secure updates are keyed.** One ticket refresh updates both the portal button and the
  travel button; the previous single slot meant the second call silently discarded the first.
- `flushPendingSecureUpdate` replays deferred updates *before* building a deferred window. The old
  order was only safe because `runWhenOutOfCombat`'s immediate path clears its key before the replay
  loop captures anything — an invariant in another function that a future caller could break.

### Standing-city filtering (`16e67c2`)

A customer standing in a city they also named is telling us where they are. That city is dropped
from the chips, even when it is the selected one, so long as another candidate remains. **It never
rewrites the selected destination** — only a chip click does that. When filtering leaves the
selection off the row, the plain destination label stays visible so the current pick is never
invisible.

Consequence to know: `wtb portal sw if` from someone standing in Stormwind shows `Destination: sw`
with a single clickable `if` chip. The portal button still casts Stormwind until you click it. The
correction is offered, not applied.

### Travel whisper (`5644bcb`)

Customisable `travelMessage`, with `%location%` for the city being travelled to and `%destination%`
still meaning where the customer is going.

- Sent at **cast start**, not completion. A teleport takes about ten seconds and that wait is
  exactly when a customer gives up and leaves. A cancelled cast leaves a promise unkept, which is
  rare and recoverable.
- Armed in **`PreClick`**, not `PostClick`: the secure action starts the cast on click and
  `UNIT_SPELLCAST_START` can dispatch before a `PostClick` handler runs.
- Scoped to the click, not the spell. A manual teleport from the spellbook whispers nobody, and
  only the one customer whose button was used is messaged.
- An armed intent that never becomes a cast expires on a `C_Timer` keyed to its own token, so a
  superseded arming's timer cannot clear the one that replaced it.
- Success, failure and interruption clear the intent only when the spell that ended is the one that
  was armed.

---

## 5. Architecture rules

**One ticket owns one customer, one destination decision, one location, one service state, one
transaction.** The queue organises tickets; features enrich that model rather than creating separate
automation systems competing for control.

**Durable facts are stored on the ticket. Derived state is computed from live sources.**

| Store | Compute |
|---|---|
| request time, original message | current location, zone, inferred city |
| selected destination | distance |
| `destinationLocked` (a deliberate user choice) | spell availability |
| payment and travel status | group capacity |
| | portal usability |

This one was learned the hard way: an early version cached `inviteData.currentCity` on the record
and it was correctly rejected in review. The lifecycle refactor is where the temptation peaks.

**Protected frames need all-Frame anchor chains** — see §4.

**The addon recommends; the seller decides.** No silent destination rewrites, no automatic
teleporting, targeting, banning, or ticket switching while the user is interacting.

---

## 6. API reference

| Symbol | File | Purpose |
|---|---|---|
| `Utils.findAllKeywordPositions(msg, list)` | `Utils.lua` | All distinct keywords in message order, longest match wins |
| `Utils.findRequestedDestination(msg, list)` | `Utils.lua` | → `(position, keyword, originOnly)`; understands from/to |
| `Utils.dedupeDestinationCandidates(cands, selected)` | `Utils.lua` | Collapse aliases for one city, preserving the selected alias |
| `Utils.rejectCurrentCityCandidates(cands, city)` | `Utils.lua` | Drop the city the customer stands in; never to zero |
| `Utils.DestinationAliases` | `Utils.lua` | All 41 shipped keywords → canonical city |
| `Utils.PortalSpells` | `Utils.lua` | Canonical city → spell data, Shattrath by faction |
| `Utils.resolveCanonicalDestination(keyword)` | `Utils.lua` | Keyword → canonical city, or nil for custom keywords |
| `Utils.matchPortalByHeuristic(dest)` | `Utils.lua` | Isolated legacy letter-scoring fallback |
| `Utils.getMatchingPortal(dest)` | `Utils.lua` | → `{matched, spellID, spellName, locationName, canonical}` |
| `Utils.getPartyUnitToken(name)` | `Utils.lua` | Ticket name → `party1`–`party4` |
| `Utils.getUnitZoneName(unit)` | `Utils.lua` | Unit **token** → zone name |
| `Utils.resolveCityFromZoneName(zone)` | `Utils.lua` | Zone name → canonical city |
| `Utils.getCustomerCity(sender)` | `Utils.lua` | The whole name → token → zone → city chain |
| `Utils.isSpellKnownByName(name)` | `Utils.lua` | Spellbook scan, ignoring rank |
| `Utils.getKnownTeleportSpell(city)` | `Utils.lua` | `Teleport: X` if the mage knows it |
| `Utils.cancelDistanceTicker()` | `Utils.lua` | Stop the live distance ticker |
| `Utils.replacePlaceholders(msg, dest, location)` | `Utils.lua` | `%destination%` and `%location%` |
| `UI.runWhenOutOfCombat(key, fn)` | `UI.lua` | Keyed deferral of protected mutations |
| `UI.flushPendingSecureUpdate()` | `UI.lua` | Replay on `PLAYER_REGEN_ENABLED`, then build any deferred window |
| `UI.updateRequestText(inviteData)` | `UI.lua` | The quoted request |
| `UI.updateDestinationChoices(sender, data, city)` | `UI.lua` | Chips, overflow picker, label retention |
| `UI.updateLocationLine(sender, label)` | `UI.lua` | Distance or `In: <zone>`, plus the travel button |
| `UI.hideTravelButton()` | `UI.lua` | Unconditional clear-and-hide |
| `InviteTrade.beginTravelAnnouncement(...)` | `InviteTrade.lua` | Arm on `PreClick`; returns its token |
| `InviteTrade.announceTravelStart(spellName)` | `InviteTrade.lua` | Whisper once on `UNIT_SPELLCAST_START` |
| `InviteTrade.clearTravelAnnouncement(sender, spell, token)` | `InviteTrade.lua` | Each filter optional but exact |

**Runtime fields on a ticket:** `destinationLocked`, `travelled`, `hasPaid`, `hasJoined`,
`timestamp`, `originalMessage`. **Runtime UI state:** `UI.pendingTicketWindow`,
`UI.pendingSecureUpdates`.

**Constants:** `REQUEST_TEXT_MAX_CHARS = 60`, `DESTINATION_CHIP_SPACING = 4`,
`DESTINATION_CHIP_PADDING = 6`, `DESTINATION_CHIP_MAX = 4`, `DESTINATION_ROW_WIDTH = 180`,
`TRAVEL_ANNOUNCEMENT_WINDOW = 2`, ticket frame 220×340.

**Events registered** (`ThicPortals.lua`), all 18: `CHAT_MSG_SAY`, `CHAT_MSG_YELL`,
`CHAT_MSG_WHISPER`, `CHAT_MSG_CHANNEL`, `PARTY_INVITE_REQUEST`, `GROUP_ROSTER_UPDATE`,
`TRADE_SHOW`, `TRADE_ACCEPT_UPDATE`, `VARIABLES_LOADED`, `PLAYER_ENTERING_WORLD`, `SPELLS_CHANGED`,
`UNIT_SPELLCAST_SUCCEEDED`, `UNIT_SPELLCAST_START`, `UNIT_SPELLCAST_FAILED`,
`UNIT_SPELLCAST_INTERRUPTED`, `UI_INFO_MESSAGE`, `PLAYER_TARGET_CHANGED`, `PLAYER_REGEN_ENABLED`.

`Events.lua` also has branches for `CHAT_MSG_PARTY` and `TRADE_MONEY_CHANGED`, neither of which is
registered — see §12.

---

## 7. Tests

Three standalone suites, no framework, run with the system `lua`:

```sh
lua tests/test_destination_parser.lua   # 17 parser + invite integration cases
lua tests/test_portal_matcher.lua       # 41 aliases, 4 regressions, faction split, custom
                                        # fallback, dedupe, 16 zone lookups, standing-city
                                        # rejection, placeholders
lua tests/test_travel_state.lua         # unit tokens, keyed deferrals, stale-update guards,
                                        # flush ordering, scoped travel announcements
luac -p Config.lua Events.lua InviteTrade.lua ThicPortals.lua UI.lua Utils.lua tests/*.lua
```

Several guards were **mutation-tested** — the guard was deliberately broken to confirm the suite
catches it. Removing the exact-spell filter fails 12 checks, the expiry window 5, the token check 3,
the scheduled timer 1, and inverting the flush order fails the ordering assertion.

Two lessons worth keeping:

- An end-state assertion for the flush-ordering bug did **not** discriminate, because
  `runWhenOutOfCombat`'s immediate path clears its key before the replay loop captures anything.
  The test asserts the ordering contract directly instead. Verify a new test fails against the
  unfixed code before trusting it.
- One test blanked `travelMessage` to prove the feature can be disabled and did not restore it,
  silently disabling every check after it. `reset()` now restores it.

---

## 8. Not verified

**Combat.** Still the least-evidenced code, and the surface has grown: `UI.pendingTicketWindow`
deferring window creation mid-fight, `runWhenOutOfCombat`, the `PLAYER_REGEN_ENABLED` flush, and now
the travel button. Deliberately deprioritised — a portal seller is in a capital city — but three of
the four in-client findings this session were in code that looked correct on paper.

**Theramore and Stonard as travel targets.** The spells exist in TBC Anniversary. Whether
`C_Map.GetBestMapForUnit` reports `Theramore Isle` / `Stonard` or the parent zone
(`Dustwallow Marsh`, `Swamp of Sorrows`) is unknown. It degrades to no button either way, and the
tests assert the safe behaviour.

**Non-English clients.** `resolveCityFromZoneName` compares localised map names against English
canonical names, so on a localised client the travel button silently never appears. Documented
limitation; a map-ID location layer would fix it.

---

## 9. Roadmap

Agreed order. The organising purpose: *help a portal seller decide whom to serve next, reach them,
complete the transaction, and avoid mistakes — with minimal attention and chat spam.* Features that
turn the addon into an advertiser, CRM, or general mage utility stay secondary.

1. ~~Update this handoff~~ ← you are here
2. **CI** — a `tests/run.sh` and a GitHub Actions workflow running `luac -p` plus the three suites.
   Cheap, and a green check makes upstream PRs easier to accept.
3. **`/tp parse`** and manual ticket controls (`/tp add`, `/tp remove`, `/tp destination`,
   `/tp list`). `/tp parse` should print origin, destination, candidates and decision. Deliberately
   early: diagnosing a mis-parse currently requires hand-written `/run` one-liners, and every
   parser-touching item after this gets cheaper.
4. **FIFO ordering and wait times.** `updateTicketList` currently does a plain `table.sort`, so the
   queue is alphabetical and reshuffles as customers come and go. `timestamp` already exists.
5. **Per-ticket portal tracking.** `Config.CurrentAlivePortals` is keyed globally by spell name, so
   casting Stormwind for one customer flips every Stormwind ticket. Pulled out of the lifecycle
   refactor because it is an active bug and much smaller.
6. **Capacity awareness.** `maxSimultaneousTickets` defaults to 15; a party holds four others, and
   there is no group-size check anywhere. Past four the addon fires invites that cannot succeed and
   burns the customer's cooldown until the 180-second expiry. Stop sending doomed invites and show
   remaining capacity. Raid conversion is deliberately *not* in this step.
7. **Trade and tip handling.** `checkTradeTip` reads only `GetTargetTradeMoney`, so an item tip is
   treated as no tip and the customer gets the no-tip whisper. Also nil-safe money handling, and
   `TRADE_MONEY_CHANGED` is handled in `Events.lua` but never registered. Do not guess item gold
   values; track item tips as their own category.
8. **Reagent warnings.** Rune of Portals and Rune of Teleportation counts, thresholds, tooltips, a
   warning before opening the shop. The `GetItemCount` machinery already exists for food and water.
9. **Explicit ticket lifecycle.** `Invited → Joined → Traveling → Nearby → Portal Cast → Paid →
   Complete`, replacing the loose booleans.
10. **Location-aware queue overview** — grouped by customer location, showing wait, status and
    whether teleport assistance is available. Never auto-switch the ticket being handled.
11. **Optional raid conversion** — user-controlled, default off, handles missing leadership,
    warns that it affects customers doing ordinary party content.

Later, in rough order: proximity/readiness states, conservative nearby-city suggestions
(`Teldrassil → Darnassus`, explicit mapping only), better ambiguity presentation, ticket aging and
no-show workflow, session statistics (after the lifecycle makes the data trustworthy), one-click ban
with history but no automatic bans, and a decision on whether to rehabilitate or delete food/water
support.

**Explicitly deprioritised:** an advertising broadcaster (pulls toward unattended operation, which
the existing AFK protection actively fights), a CRM/customer-rating system, and the global namespace
refactor (real, but invasive and invisible).

**Cheap win not yet done:** `handleCommonPhraseInvite` runs the destination scan unconditionally,
even when the phrase did not match, and the advanced path runs it again. Measured at 110µs per scan
versus 6µs for the phrase check, on every trade-channel message. Make it lazy, add a regression
test, do not rewrite the parser.

---

## 10. Setup on this machine

Arch Linux, WoW via a Proton/Battle.net prefix. The earlier Windows/PowerShell instructions are
gone; so is the Mac-only `~/Developer/thic-portals-work` workspace, whose `notes/Findings.md`,
`notes/PR-Plan.md` and `tools/matcher_sim.py` are **not** on this machine.

**Client:** `_anniversary_`, TBC **2.5.6.69110**, Interface **20506** — already covered by the
`.toc`, no change needed. Note there is a *second, stale* WoW install at
`/mnt/gamedrive/battlenet/World of Warcraft/` with no ThicPortals in it. Ignore it.

**AddOns:**

```
/home/legault/.steam/steam/steamapps/compatdata/4004364414/pfx/drive_c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns
```

`AddOns/ThicPortals` is a **symlink** to `/home/legault/Projects/thic-portals`, so there is one
working copy: edit the repo, `/reload` in game. Wine follows it fine.

The stock CurseForge 3.4.2 folder was moved to `/home/legault/Projects/thicportals-stock-backup/`
along with copies of the SavedVariables. Note the stock package is *older* than upstream git master
— it predates the `Utils.print` refactor in PR #13.

**SavedVariables** (untouched by swapping the addon folder):

```
.../_anniversary_/WTF/Account/986502692#1/SavedVariables/ThicPortals.lua
```

**Before testing:** `/console scriptErrors 1`, then `/Tp debug on` — debug mode is not persisted
across reloads. The addon always boots with the shop **closed** regardless of the saved
`addonEnabled`, so left-click the toggle icon (bottom-centre) to open.

**Testing without a customer:** a fake ticket can be injected, but anything touching location needs
a real party member, because `UnitInParty` is false for a fabricated name.

```
/run Events.pendingInvites["Testcustomer"]={name="Testcustomer",fullName="Testcustomer-Test",destination="if",originalMessage="wtb port from sw to if",hasJoined=true} UI.showPaginatedTicketWindow()
/run Events.pendingInvites["Testcustomer"]=nil UI.updateTicketList() UI.updateTicketFrame()
```

The cleanup above removes only the fake — do **not** use `Events.pendingInvites={}` while live
customers are in the queue.

**Location diagnostic**, with a real customer on the ticket:

```
/run local U,s=Utils,UI.ticketFrame.currentSender local u=U.getPartyUnitToken(s) local z=u and U.getUnitZoneName(u) local c=z and U.resolveCityFromZoneName(z) print(s,u,z,U.getUnitZoneName('player'),c,c and U.getKnownTeleportSpell(c))
```

Prints `sender, token, theirZone, yourZone, city, teleportSpell`. Token nil means name resolution
failed; token set with zone nil means the map API declined for party units, and the fallback would
be `UnitPosition` proximity against city coordinates.

**Toolchain:** `lua` (5.5.0) and `luac` are on `PATH`; no install needed.

---

## 11. Upstream — open decision

**Not decided. Do not slice PRs without inspecting each commit's dependency graph first.**

The original plan assumed two PRs from two feature branches. There are now ten commits, and the
later ones build on the earlier: the chip filter needs the location layer, which needs the keyed
deferral, and chip dedup depends on the matcher rewrite. Some commits are genuinely independent and
some only look it.

Likely narrow candidates, in rough order of independence:

- **`4e59127` tooltip arity** — pure upstream bug, one line, no dependencies. Best first PR.
- **The matcher fix** (`2454625`) — self-contained, ships its own tests, fixes `org` for every Horde
  seller. Chip dedup depends on it, but the matcher does not depend on the chips.
- **The from/to parser** (`c570dd8`) — the original PR 2.
- **Capacity guard** (roadmap item 6, not yet written) — small and independently valuable.
- **Item-tip correction** (roadmap item 7, not yet written) — small and customer-facing.

The maintainer has only ever merged narrow PRs and has been unresponsive since April, so
single-purpose is the right shape if this goes upstream at all. If the first PR gets no reply in
about two weeks, ping the Discord rather than stacking more.

**GitHub account:** everything ships from `legault12` / `legault12@gmail.com`, never the work
account. On this machine `gh` has only `legault12` authenticated and active, and the global git
identity matches, so the account-mixing trap from the Mac does not exist here — but verify before
pushing:

```sh
gh api user --jq .login      # must print legault12
git log --format='%an <%ae>' -3
```

---

## 12. Known issues not addressed

Carried forward, with the resolved entries removed.

| # | Issue |
|---|---|
| 1 | `Config.CurrentAlivePortals` is global by spell name, not per ticket — roadmap item 5 |
| 2 | `maxSimultaneousTickets` exceeds party capacity with no group check — roadmap item 6 |
| 3 | Item tips are not counted; a tipping customer gets the no-tip whisper — roadmap item 7 |
| 4 | `checkTradeTip` does `tonumber(nil)` arithmetic if no accept-update fired |
| 5 | `TRADE_MONEY_CHANGED` is handled but never registered — dead branch |
| 6 | `matchFoodAndWaterRequests` is dead code and would error if called (`for k in table do`) |
| 7 | `UI.showFoodWaterRequest` is dead code that does not do what its name says |
| 8 | Food and water prices reset to defaults on every login (`Config.lua` overwrites the saved table) |
| 9 | Chat spam not gated on debug mode — raw `print` on login and on `ThicPortalsSaved` init |
| 10 | `CHAT_MSG_PARTY` handled but never registered — dead branch |
| 11 | Ticket Remove button is disabled unless the customer `travelled`, so a paid non-traveller cannot be dismissed |
| 12 | `findKeywordPosition` does not escape pattern characters, unlike `findAllKeywordPositions` |
| 13 | `Config.Settings` aliases `DEFAULT_SETTINGS` on first run; missing keys are patched by a hand-maintained list |
| 14 | Unprefixed globals `Config`, `UI`, `Events`, `Utils`, `handleCommand` |
| 15 | `approachMode` in defaults is never read; the code uses `ApproachMode` |
| 16 | `if` as an Ironforge keyword is a false-positive magnet in ordinary sentences |
| 17 | README claims a 3-strike AFK threshold; `leaveWithoutPaymentThreshold` is 2 |
