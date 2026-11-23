# GuildDB

Roster profile specs use a dropdown with your class's three talent trees. GuildDB detects and shares your main spec from the tree with the most spent talent points, refreshing when talents change. A manual dropdown choice lasts until your talent allocation changes. Tied, unspent or unavailable talent data does not force a main spec. Other members running the updated addon share their own detected specs; offline or non-addon members retain their last saved profile.

Use `/gd spec` to print your detected main spec, the points spent in each talent tree, and your saved profile spec (including any active manual override). This diagnostic only prints locally; it does not change or share your profile.

GuildDB is a World of Warcraft guild addon for a shared roster, member profiles, announcements, raids, events, shoutouts, and guild utilities. It is designed to work independently for any guild.

## Features

- Recruitment is visible only to the GM and rank 1 officers, matching GuildDB's officer permissions. Open it with `/gd recruit`. Search Who or import the game's current Who results to save unguilded candidates, or add a full character name manually. Search saved candidates and choose a status from the themed dropdown to review contacts, replies, skipped candidates, and Do Not Contact entries. Whisper and Guild invite each require a click; invites also require the game's guild-invite permission. Contact statuses indicate submitted actions, not confirmed delivery or membership.
- Recruitment includes private notes and saved whisper/ad templates with `{name}` and `{guild}` placeholders. Save templates before sending. Post ad uses the joined channel number you enter and has a five-minute cooldown. Candidate data, latest replies from previously contacted players, templates, and cooldowns are saved locally per recruiter and guild; they are not sent through guild sync. Other officers maintain their own lists. Recruitment pauses contact actions and ads in combat.
- Recruitment separates Candidates and Messages into two pages, with bordered work areas for finding players, the candidate list, selected-player actions and notes, whisper templates, advertisements, and contact limits. Its boxes, inputs, labels, and selected rows follow the active theme and accent. Workspace scrollbars share a compact accent-colored thumb, support dragging and the mouse wheel, and hide when their content fits.
- Recruitment Who searches replace the visible results instead of accumulating previous searches. A single level such as `22` matches that level exactly; inclusive ranges such as `1-60` or `50-60` exclude levels outside the range and unreadable levels. Other Who filters use the latest results returned by the game. Editing the Who filter hides the previous results until you run the new search; waiting, empty, and timed-out searches never show the older list. Saved list returns to all saved candidates, with the status dropdown and saved-candidate text search still applied. Contact history, skips, Do Not Contact, and cooldowns are preserved when switching searches.
- Skip blocks contact for one hour; Do Not Contact blocks whispers and invites until Restore is explicitly clicked. Restoring or reimporting a candidate never clears contact cooldowns. There is a ten-second delay between contact actions, a 24-hour cooldown per candidate for each action (whisper and invite separately), and a daily limit of 50 actions per recruiter, resetting on the client's local date. Limits survive reloads. Who searches have a ten-second delay, and clients without readable Who APIs can still add candidates manually. No messages or invitations are sent automatically.
- Online-only guild roster with GuildDB presence and reported addon version.
- Roster filters combine class, role (including Unknown), level range, and profession with the existing search and Online Only setting. Clear filters resets the four filters while preserving search and Online Only. The result count includes characters; role and profession rely on shared profiles. Filters stay active while switching tabs during the current session and are not sent to guild peers.
- Minimap launcher: enabled by default and registered as GuildDB through bundled LibDataBroker/LibDBIcon libraries, including in minimap-button menus. Left-click toggles GuildDB, right-click opens Settings, and dragging repositions it around the minimap. Its position survives reloads. Show or hide it under Settings → Personal → Show minimap button; `/gd` still works when the button is hidden.
- Opt-in guild member location sharing with fresh reports, World Map pins, and waypoint navigation.
- Member profiles for role, specialization, time zone, alts, and listed professions or recipes.
- Home dashboard above Roster with a message of the day, officer announcements, and recently observed new members.
- The guild master and officers can always edit the MOTD. Home's Save button submits the game's MOTD command directly from your click and requires the game's Edit MOTD permission. Home displays the current guild MOTD, including changes made through the game's guild window.
- Recently joined tracks members from the 0.1.88 release onward, using a shared release cutoff. Earlier joins are excluded automatically. Names show class colors and levels. Live notifications and available guild history supply joins; guild-log entries too imprecise to place after the cutoff are excluded. Records are retained for 30 days.
- Analytics shows guild makeup with class, race, spec, role, and level charts. Switch between all roster members and online members; hover a chart row for its count and percentage. Race, spec, and role use shared profiles, with missing values counted as Unknown. Counts represent characters, including alts.
- GuildDB can open, close, refresh, and switch tabs during combat. Protected guild-rank actions stay hidden until combat ends.
- A guild guide for rules and loot rules.
- Guild Info has separate Guild Info and Guild Rules pages, editable by the GM and rank 1 officers. Empty installations include starter guild rules and an introduction explaining that the guild is growing and GuildDB is a work in progress. Existing saved information is preserved; edits are shared with guild peers. Each page keeps its own unread status.
- The guild master can save or remove a Discord server invite under Settings → GM. A Join Guild Discord button using the shared button style and selected accent color stays in the window header on every tab and is disabled until an invite is configured. It opens a selected, copyable link with Ctrl+C instructions. Invites sync with guild data; only rank 0 can set them.
- Raid creation and signup area with raid size targets, player specs, Tank/Healer/DPS roles, attendance, and signup notes. The GM can check players for the invite roster; selections are shared with the guild.
- PvP leaderboard with outdoor kills, deaths, K/D ratios, seasons, and a Most Wanted list. K/D is kills divided by deaths, using one as the denominator until the first death. Shared honorable kills count as kills; assists are not tracked separately.
- PvP includes Leaderboard, Bounty Board, and Nemesis views. Bounties open automatically when an enemy has killed guild members three times, including repeat kills of the same member. Three deaths gives +3 bonus points, five gives +5, and the reward caps at +10. No officer creates, approves, or edits rewards. The first subsequent credited outdoor kill freezes the reward; every guild member receiving kill credit in that defeat's 10-second credit window gets the full bonus once. The enemy's death counter restarts after a claim; new deaths build the next bounty. There is no daily payout cap or expiry. Bounties span seasons; each member's bonus counts toward the season containing their credited kill and all-time points.
- The leaderboard ranks by total points (kills + bounty bonuses), showing points separately from kills, deaths, and K/D. Nemesis shows your kills and deaths against each enemy, sorted by Most killed or Killed me most, for the selected season or All-time. Bounty Board shows the current guild-wide counter, bonus and status: OPEN, CLAIM (collecting shared credit), or PAID. Enemies with only one or two guild kills are tracked internally and hidden until the third opens a bounty; fresh counters after a payout also stay hidden until they reach three.
- Bounty combat evidence is saved separately from the capped activity feed and synced for consistent awards after reload, history trimming and out-of-order delivery. Retained events seed the initial history, but discarded encounters cannot be reconstructed from cumulative counters. All participants should update for complete bounty evidence and matching leaderboards. Shared defeats are grouped by enemy name and event timestamps; the client does not provide a shared kill-credit ID. Deleting a season keeps all-time bonuses; Wipe All Stats also clears bounty evidence and rejects stale pre-reset packets.
- Updated members save and sync cumulative enemy totals beyond the recent-history cap. Retained history seeds personal totals on upgrade; discarded encounters cannot be recovered. Members on older versions contribute retained encounters only. Full names including realms remain distinct. Deleting a season removes its rivalry totals; Wipe All Stats also clears rivalries.
- Outdoor PvP deaths count once per life when you took player or player-controlled pet damage in the preceding 30 seconds. Death records and season/all-time totals sync automatically with guild peers. Detection requires readable combat-log damage events from the client.
- Looking For group board; posts expire after three hours.
- Crafting request board; requests expire after seven days and can be claimed by crafters.
- Officer polls appear as individual cards with colored horizontal bars, option names and vote totals above each bar, and a Vote button beneath it. Bar lengths show each option's share of the votes, with percentages beside the totals. Use the buttons to vote or change your choice; your selection is marked Voted. Each poll has separate Close and Delete controls for the GM and rank 1 officers. Closing preserves that poll's results; deleting removes it and syncs the deletion so old history cannot restore it. Voter names are not shown in the interface.
- Shoutouts between guild members.
- Raid Info, Guild Info, and Polls show a NEW badge for unseen content. Opening a section marks its current content as read. Read status is saved per character and guild across reloads. Upcoming raid/event creations and edits, Guild Info revisions (including clearing the page), and new or closed polls trigger badges; votes and signup changes do not. Existing content is unread until first opened; expired events and deleted records do not trigger badges.
- Pop-up notifications for new guild announcements and events, stacking PvP rewards, and guild-wide level/profession milestones for members running GuildDB.

Officers (guild leader and rank 1) can create announcements, schedule raids and events, edit the guide, create or close polls, and start PvP seasons. Any guild member can edit their own profile, RSVP, vote, make or claim board requests, and post shoutouts.

Guild data syncs between members running GuildDB using in-game addon messages. There is no external server. Offline members catch up from an online rank 0 or rank 1 member when they sync. Board requests expire automatically.

In Events, officers use Create raid to schedule a raid and set its signup lock and size target. Creation defaults to also creating an in-game guild-calendar signup event; choose GuildDB only to skip it. The creator can retry with Create calendar if the client cannot create the calendar copy. Calendar writes require the client's guild-calendar APIs and game permissions.

Members use Sign up / Change to choose Going, Maybe, or Absent, write their spec, choose Tank/Healer/DPS, and add an optional note. Class is detected automatically from the guild roster; player and class columns use class colors. Role totals count Going players only, with older signups missing a role counted as Unassigned. Members can change an existing signup even when new signups are locked, or use Remove my signup to withdraw. The GM can remove anyone's signup. Removal records are synced to prevent older history from restoring a withdrawn signup; members can sign up again while signups are open.

Only the GM can change the invite checkmarks, and only Going players can be selected. Checkmarks record the planned invite list and do not automatically invite players. All participating members should update GuildDB to exchange the expanded signup data, removals, and GM selections. Raid size is a planning target, so additional members can still sign up. Withdrawing your own signup attempts to decline the matching native calendar event; GM removal affects the GuildDB roster.

GuildDB remembers each character's last reported addon version in the saved data for that guild, including your own characters as you log into them. The roster's Online only filter can be turned off to see offline characters and their saved versions. Member details label an older report as "last known" when there is no recent announcement; this does not prove the addon is still installed. Characters not yet detected show X in the version column. Saved reports do not generate extra messages, and only recent live announcements are used to select sync responders.

GuildDB announces its version and full character name at login and once per minute. Login and guild joins retry discovery during the first 25 seconds; opening GuildDB also requests replies from online peers. Older clients still receive the original version announcement. Use `/gd presence` to inspect prefix registration, outgoing announcements, and incoming guild packets when diagnosing detection problems.

At login or UI reload, GuildDB prints a colored welcome message with `/gd` and your installed version. Use `/gd version` to display your installed version again.

Select a member in Roster and choose a rank from Set Guild Rank. Each hardware click submits one secure rank step and refreshes the roster from the game. If the chosen rank is several steps away, the same control shows Continue to the chosen rank; click again after each confirmed step until it is reached. This avoids sending several commands against the same stale rank. Guild permissions still apply, and rank changes are unavailable during combat. The dropdown stays inside GuildDB and remains open during ordinary background refreshes.

PvP rankings use total eligible kills plus automatic bounty bonuses, regardless of victim level. Each kill contributes one base point; existing kill totals are preserved and historical level-based points no longer affect rankings. Only game-credited open-world kills count; battlegrounds, arenas, dungeons, raids, and scenarios are excluded. Honor messages and kill-credit updates are combined to avoid counting the same reward twice. Counter-only credits require one identifiable recent enemy death. Victim levels come from recently visible enemy players; unknown levels use your level, and skull-level enemies use your level plus 10, capped at 60. Every eligible kill counts, including repeated kills of the same victim, with no per-victim cooldown or daily cap. The detailed activity feed keeps up to 60 recent kills and deaths per guild. Leaderboard kill, point, and death totals are cumulative per member and season, synced separately from that feed. Existing saved recent records are folded into a member's totals the next time they record a PvP event; older records already discarded by the 60-entry cap cannot be recovered. A new season starts fresh at its start time.

## Install for development

Release versions use `0.2.NN`, starting at `0.2.01`. Increment the final number after every five completed addon features or fixes, keeping the TOC version and `GD.version` in sync. Track progress toward the next bump in AGENTS.md; instruction-only and documentation-only updates do not count.

Copy this folder into the client's `Interface/AddOns` directory, enable **GuildDB** on the AddOns screen, and join a guild.

## Commands

- `/gd` opens GuildDB; `/gd sync` requests recent guild data.
- `/gd version` shows your installed version.
- `/gd bankapi` checks guild-bank API availability, event registration and events observed since its first use this session, and reads the selected tab's item links and counts locally. Run once before opening the guild bank, then open a populated tab and run it again. `/gd bankapi query` requests that selected tab's data while the bank is open; wait for the response, then rerun `/gd bankapi`. This diagnostic does not move items, save snapshots, or share bank contents. Runtime results are needed to confirm Forever compatibility.
- `/gd post Message text` posts an announcement (officer).
- `/gd event YYYY-MM-DD HH:MM | Title | Details` schedules an event (officer).
- `/gd raid YYYY-MM-DD HH:MM | Title | Details` schedules a raid (officer).
- `/gd rsvp # going|tentative|absent` responds to an upcoming calendar entry.
- `/gd profile set Role | Spec | Time zone | Alts | Professions` sets your member profile.
- `/gd profile Name` views a member profile; `/gd profile list` returns to the directory.
- `/gd guide` opens the guild guide; `/gd guide set Rules | Loot rules` updates it (officer).
- `/gd looking Role | Activity | Details` posts a group request; `/gd looking close #` closes your post.
- `/gd craft request Item | Details` posts a crafting request.
- `/gd craft claim #` claims a request; `/gd craft done #` closes it.
- `/gd craft who Recipe` searches online members' listed crafting skills.
- `/gd poll create Question | Option 1 | Option 2 [| Option 3 | Option 4]` creates a poll (officer).
- `/gd poll vote # option#` votes; `/gd poll close #` closes a poll (officer).
- PvP → New Season creates a season (guild master only): enter its name, pick an end date from the calendar, and click Start. Existing seasons and all-time totals are kept. The end date includes that entire day in the creator's local time. When the deadline passes, new kills count toward all-time stats only; the finished season remains visible. All members must update for the cutoff to apply consistently.
- `/gd pvp wipe CONFIRM` permanently clears all guild PvP points, kills, deaths, recent records, and seasons (guild master / rank 0 only). The saved reset syncs to updated members, including members who return later; older clients must update to honor resets. Repeat-victim history clears when a client receives the reset.
- PvP → Delete Season lets the guild master choose a season and confirm its deletion. All-time stats are kept. The button is disabled when no seasons exist.
- PvP → Wipe All Stats lets the guild master clear all PvP stats and seasons after confirmation. Click New Season afterward to begin a new Season 1. These three buttons are grouped at the bottom of the PvP screen.
- `/gd shout Player Name | Message` posts a shoutout.
- `/gd map waypoint CharacterName` sets a waypoint to a member's latest shared location; `/gd map clear` clears it.
- `/gd popout pvp`, `/gd popout level10` (also 20/30/40/50/60), or `/gd popout profession150` (also 225/300) previews a popout locally.
- `/gd testpopout level` or `/gd testpopout profession` sends a milestone popup test to online GuildDB users (guild leader/rank 1).

Personal Settings can turn GuildDB popups on or off, optionally share your map location with GuildDB members, and optionally send a guild-chat “Ding!” for level milestones. Map sharing is off by default, pauses in instances, and reports expire after 45 seconds. Profession milestones never send guild chat messages.

Date and time in event commands use the local time shown by the game client. Board item numbers refer to the current order shown in their tab.

## Project layout

- `Core/Runtime.lua` provides addon lifecycle, saved data, slash routing, and guild message sync.
- `Features/` contains independent modules for profiles, announcements, events, shoutouts, PvP, guild guide, group requests, crafting, and polls.
- `UI/Main.lua` builds the shared window, navigation, and roster view.
- `GuildDB.toc` lists the files in WoW load order.
