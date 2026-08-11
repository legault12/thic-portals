# Thic-Portals — testing handoff

Context for continuing this work on the gaming PC. Written 2026-08-11.

**Status: nothing is merged, nothing is proposed upstream.** A fork exists under the
personal account and one test branch is pushed to it. No pull request has been opened
anywhere. The next step is in-client testing, which could not be done on the Mac where
this was written (no WoW install).

---

## 1. What this is

[Thic-Portals](https://github.com/MattGarnettWelsh/thic-portals) is a mage portal-service
addon for WoW Classic TBC Anniversary. It watches trade/say/whisper chat for portal
requests, auto-invites the customer, and shows a "ticket" with a big button that actually
casts the portal.

Upstream is `MattGarnettWelsh/thic-portals`, default branch `master`, addon version 3.4.2,
last pushed 2026-04-07 and quiet since. Two PRs (#12, #14) from `jdorsman` have sat open
and unanswered since April. Maintainer contact: Thic-Ashbringer (EU) in-game, or Discord
`https://discord.gg/RjfDtUmH`.

## 2. The problem we set out to fix

The ticket showed only the single destination keyword the addon pulled out of the request.
For a request like `wtb port from sw to if`, that keyword is `sw` — which is where the
customer is *standing*, not where they want to go. Confirming it meant scrolling back
through trade chat to find the original message, which in a busy zone is the single most
annoying part of using the addon.

## 3. Two different bugs that look identical

This distinction matters and is easy to lose. **Only the first is addressed here.**

**A. Extraction — which word gets picked out of the message.** `Utils.findKeywordPosition`
returned the first keyword in *`Config.DestinationKeywords` list order* that appeared
anywhere in the message. With two cities named, config ordering decided the destination,
not the customer's wording.

An important finding: the obvious fix — order by position in the message instead — does
**not** fix the reported case. In "from sw to if" the wrong city genuinely comes first.

| request | original | "earliest in message" | correct |
|---|---|---|---|
| `wtb port from sw to if` | sw | **sw** | if |
| `sw to if pls` | sw | **sw** | if |
| `need tp to shatt from org` | org | shatt | shatt |
| `lf port if, in sw now` | sw | if | if |

The preposition is load-bearing. That's what drove the design.

**B. Matching — a correct word mapped to the wrong spell.** `Utils.getMatchingPortal`
(`Utils.lua`) scores portals by counting how many letters of the request appear *anywhere*
in the city name, ignoring order, double-counting duplicates, and breaking ties by position
in `Config.Portals`. Result:

| request | should cast | actually casts |
|---|---|---|
| `org` | Orgrimmar | **Ironforge** |
| `orgri` | Orgrimmar | **Ironforge** |
| `sm` | Silvermoon | **Stormwind** |
| `ston` | Stonard | **Stormwind** |

`org` is the most common Horde request there is. **This is still unfixed** — it is a
separate future PR (see `notes/Findings.md` §1 in the workspace repo, and
`tools/matcher_sim.py` which reproduces the table). Do not conflate it with A.

## 4. What was built

Three branches. The test branch is the tip and contains everything.

```
master (7cdc9a8, upstream)
 └─ ticket-show-original-request   46ccf28   → future PR 1   [local only]
     └─ destination-from-to-parsing c570dd8   → future PR 2   [local only]
         └─ test/ticket-destination 5a15e2d   → PUSHED to fork
```

### PR 1 — `ticket-show-original-request` (46ccf28)

- **The customer's request is now shown permanently on the ticket**, under Distance,
  quoted and dimmed, truncated at `REQUEST_TEXT_MAX_CHARS = 60` with the full text on
  hover. `originalMessage` was *already* stored on every invite — it was simply never
  displayed on the main ticket. No data model change was needed.
- **Destination becomes clickable chips when a request names more than one city.** Current
  pick is gold `(1, 0.82, 0)`, alternatives grey. One click retargets the ticket. Chips
  occupy a full-width row beneath the label and divide the 180px evenly, so two long city
  names cannot overflow the narrow frame.
- **A manual pick sets `inviteData.destinationLocked`**, so a later whisper cannot silently
  overwrite it. Without this, `updatePendingInviteDestination` re-runs on *every* subsequent
  message from that player and would undo the choice.
- **New `Utils.findAllKeywordPositions`** — every distinct keyword in message order,
  longest-match-wins on overlap so "thunder bluff" is not also reported as "thunder".
  Unlike `findKeywordPosition` it escapes Lua pattern characters, so a user-added keyword
  containing `-` is safe.
- **Combat safety.** Retargeting rewrites a `SecureActionButtonTemplate`, which is
  protected in combat. Added `UI.runWhenOutOfCombat` / `UI.flushPendingSecureUpdate`,
  registered `PLAYER_REGEN_ENABLED` in `ThicPortals.lua`, handled in `Events.lua`.
- Ticket frame grew from 220×270.

**Judgement call — the envelope-icon message view was deleted (~104 lines).** Reasons: it
swapped the entire ticket, hiding Destination, the portal button and Remove, so you could
never see the request and the cast button together; it created four new FontStrings on
*every* toggle instead of reusing the ones built at creation (which were orphaned and never
used at all — WoW FontStrings cannot be destroyed, so this accumulated); and its restore
path read a `sender` variable that was not in scope. With the request always visible it is
redundant. **This is the riskiest part of the PR socially** — it removes a feature the
author wrote. Reverting to "keep and repair it" is still an option.

### PR 2 — `destination-from-to-parsing` (c570dd8)

`Utils.findRequestedDestination(message, keywordList)` → `(position, keyword, originOnly)`.
Drop-in for `findKeywordPosition` (extra return is ignored by callers that don't want it).

Scores each location by the word immediately before it:

- **Destination markers** → `to`, `2`, `too`, `>`, `>>`, `->`, `=>`
- **Origin markers** → `from`, `in`, `at`, `im`, `i'm`

Prefers the *last* marked destination, because "from A to B" puts the wanted city last.
With no markers it falls back to the first location mentioned — the original behaviour.
Swapped in at the four destination lookups in `InviteTrade.lua`. Intent and service lookups
still use `findKeywordPosition`; they are not choosing between locations.

### Test branch — `test/ticket-destination` (5a15e2d)

Rolls up review corrections that span *both* features, so they can be redistributed onto
the two clean feature branches after testing:

- Completed the combat guard — also covers **first-time ticket window creation during
  combat** (creating a `SecureActionButtonTemplate` is itself forbidden in combat;
  `UI.pendingTicketWindow` defers it) and discards stale deferred updates.
- Compact arrows: `sw->if`, `sw=>if`, `sw>if`.
- Chips constrained to the ticket width.
- Fixed UTF-8 truncation producing malformed text.
- Cleared stale action-button tooltips, icons and paid/complete indicators when navigating
  between tickets.
- Clicking the already-selected destination still locks it.
- Normalised keyword case when de-duplicating scanner hits.
- Ticket frame → **220×340**.
- Added `tests/test_destination_parser.lua`, runnable from any directory.

## 5. A regression that was caught — worth remembering

An intermediate version made `findRequestedDestination` return `nil` when *every* location
in a message was origin-marked. Correct for its stated purpose (stopping "I'm in SW" from
retargeting an existing ticket) — but that function feeds the invite-matching path too, so:

| message | became |
|---|---|
| `wtb portal in sw` | **no invite sent** |
| `wtb port in ironforge` | **no invite sent** |
| `lf mage port at if` | **no invite sent** |

`InviteTrade.lua` — `matched = destinationPosition and true or false` in Approach Mode, and
the `requireDestination` early return — both turn `nil` into a dropped customer. "portal
**in** Stormwind" is an ordinary phrasing. A silently ignored paying customer is worse than
a mislabeled ticket.

**Fix:** one function was answering two questions. It now returns `originOnly` as a third
value; matching keeps the city fallback, and only `updatePendingInviteDestination` acts on
the flag. **Lesson: any change to destination resolution must be checked against the invite
path, not just the ticket display.**

## 6. What has and has not been verified

**Done (on the Mac, standalone Lua — `brew install lua` was run for this):**

- `luac -p` clean on all six first-party files plus the test
- Every file referenced by `ThicPortals.toc` resolves, including both `Libs` entries
- `tests/test_destination_parser.lua` — 17 parser/integration cases
- Independent 18-case from/to suite — 18/18
- All 41 shipped `DestinationKeywords` in simple single-destination requests — **0
  behaviour changes** vs the original function
- `git diff --check` clean

**NOT done — this is the entire reason for the gaming PC trip:**

- Nothing has been loaded into a running WoW client, at all
- Ticket layout at 220×340 was computed arithmetically, never looked at. **Chip row and
  request-text anchor offsets are the most likely thing to be visibly wrong.**
- Chip clicks actually retargeting the secure button and casting the right portal
- The combat deferral paths — the least-evidenced code in the changeset
- Truncation and hover tooltip on genuinely long requests

## 7. Setting up on the gaming PC

You already run this addon, so **find the existing install** rather than guessing between
`_classic_era_` and `_classic_` — the `.toc` targets Interface `11506–11508` *and*
`20505–20506`, so it covers both clients.

The repo root *is* the addon folder (`ThicPortals.toc` sits at the top level), so the fork
clones straight into place — no ZIP, no renaming, no copying files.

From your `AddOns` directory:

```powershell
Move-Item .\ThicPortals ..\ThicPortals-stock-backup

git clone --branch test/ticket-destination --single-branch `
  https://github.com/legault12/thic-portals.git ThicPortals
```

Moving the backup *out* of `AddOns` keeps it from showing up as a broken entry. (WoW loads
`AddOns/<Folder>/<Folder>.toc`, so a renamed folder wouldn't load anyway — this is just
tidier.)

Your settings, gold totals and ban list are safe: SavedVariables live under
`WTF\Account\...`, outside the addon folder. Nothing here changes the SavedVariables
schema. Backing up `WTF` first is still sensible.

**Before testing:** `/console scriptErrors 1` — without it Lua errors fail silently and
you'll be debugging blind.

**Iteration loop:** `git pull --ff-only` then `/reload` in-game. No client restart needed.
Fixes can be made on either machine and moved with `git push` / `git pull`.

Optional: bump `## Version: 3.4.2` to `3.4.2-test` in the `.toc` so the in-game addon list
confirms at a glance you're on the test build. Revert before any PR.

## 8. In-client test checklist

- Single-destination ticket renders correctly (plain label, no chips)
- Multi-destination request shows chips; gold = selected, grey = alternatives
- Every chip casts the portal it claims
- Clicking a chip retargets; clicking the selected one locks it
- A follow-up whisper naming another city does **not** override a manual pick
- `wtb portal in sw` and similar origin-marked phrasings **still generate an invite**
- Long request text truncates and the hover tooltip shows the full message
- First ticket arriving **while already in combat** (window creation deferred)
- Changing tickets / destinations during combat
- Action button corrects itself on leaving combat
- No "Interface action failed because of an AddOn" anywhere
- Navigating between tickets leaves no stale icon, tooltip or paid/complete marker

## 9. After testing

The fixes in `5a15e2d` span both features. Redistribute them onto
`ticket-show-original-request` and `destination-from-to-parsing`, then open **two separate
PRs** upstream — keep them single-purpose, since the maintainer has only ever merged narrow
PRs.

**Open decisions:**

- **Envelope-view deletion** — keep the removal, or restore and repair it? Riskiest part of
  PR 1 with a quiet maintainer.
- **Ship `tests/` in PR 2?** Upstream has no test infrastructure, so it could read as scope
  creep. Counter-argument: the parser regression test documents the matching-versus-
  retargeting distinction that already bit us once, and needs no framework. Undecided.
- If PR 1 gets no reply in ~2 weeks, ping the Discord rather than stacking more PRs.

## 10. GitHub account — hard constraint

**Everything ships from `legault12` / `legault12@gmail.com`. Never `legault_battelle` /
`legault@battelle.org` (work account).**

Both accounts are authenticated in `gh` on the Mac. The work account *was* the active
default — that's the trap. As of this writing `gh` on the Mac has been switched to
`legault12`. Both clones have a repo-local git identity pinned to the personal account.

Before any push or fork:

```sh
gh auth switch --user legault12
gh api user --jq .login      # must print legault12
```

Verify authorship afterwards with `git log --format='%an <%ae>'`.

Fork created 2026-08-11: `legault12/thic-portals`, public, parent
`MattGarnettWelsh/thic-portals`.

## 11. Known issues found but NOT addressed

From the full code review in the workspace repo (`notes/Findings.md`). Context only —
none of these are in the current changeset:

| # | Issue |
|---|---|
| §1 | Destination matcher misroutes `org`, `orgri`, `sm`, `ston` (see §3B above) |
| §2 | Portal-alive tracking is global, not per-ticket — casting for customer A flips every ticket for that city |
| §3 | Distance tickers leak — a new `C_Timer.NewTicker` per `updateTicketFrame` call, and it's called from `PLAYER_TARGET_CHANGED` |
| §4 | Combat-lockdown guards — partially done here; other `SetEnabled` call sites remain |
| §5 | Food/water request detection is dead code and could not run as written (generic-for over a table) |
| §6 | Chat spam not gated on debug mode — raw `print` on every portal cast and on login |
| §7 | Food/water prices reset to defaults on every login |
| §8 | Trade tip handling — `tonumber(nil)` risk, a dead `TRADE_MONEY_CHANGED` branch, item tips not counted |

Plus a minor table in `Findings.md`: unescaped pattern interpolation in
`findKeywordPosition`, `if` as an Ironforge keyword being a false-positive magnet,
README/threshold mismatch on AFK protection, Theramore/Stonard being Wrath-era spells in a
TBC list, cross-realm `Name-Realm` handling, and the TOC interface versions needing a check
against the current Anniversary build.

## 12. Quick reference

**New/changed API**

| Symbol | File | Purpose |
|---|---|---|
| `Utils.findAllKeywordPositions(msg, list)` | `Utils.lua` | All distinct keywords in message order |
| `Utils.findRequestedDestination(msg, list)` | `Utils.lua` | → `(position, keyword, originOnly)` |
| `UI.runWhenOutOfCombat(fn)` | `UI.lua` | Run now, or defer past combat |
| `UI.flushPendingSecureUpdate()` | `UI.lua` | Replay on `PLAYER_REGEN_ENABLED` |
| `UI.updateRequestText(inviteData)` | `UI.lua` | Draw the quoted request |
| `UI.updateDestinationChoices(sender, inviteData)` | `UI.lua` | Draw/refresh the chips |
| `inviteData.destinationLocked` | runtime | User picked by hand; don't overwrite |
| `UI.pendingTicketWindow` | runtime | Window creation deferred out of combat |

**Constants:** `REQUEST_TEXT_MAX_CHARS = 60`, `DESTINATION_CHIP_SPACING = 4`, chip row
divides 180px, ticket frame 220×340.

**Run the tests:** `lua tests/test_destination_parser.lua` (needs `lua`; `brew install lua`
on Mac, or scoop/choco on Windows). Syntax check: `luac -p *.lua`.

**Workspace repo** (Mac only, not on GitHub): `~/Developer/thic-portals-work` — contains
`notes/Findings.md` (full code review), `notes/PR-Plan.md`, `notes/Review-Ticket-Destination.md`,
`notes/GitHub-Account.md`, and `tools/matcher_sim.py`.
