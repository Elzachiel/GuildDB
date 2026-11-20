# Guild Hall

Guild Hall is a World of Warcraft guild addon for a shared roster, member profiles, announcements, raids, events, shoutouts, and guild utilities. It is designed to work independently for any guild.

## Features

- Online-only guild roster with Guild Hall presence and reported addon version.
- Opt-in guild member location sharing with fresh reports, World Map pins, and waypoint navigation.
- Member profiles for role, specialization, time zone, alts, and listed professions or recipes.
- Officer announcements and a guild guide for rules and loot rules.
- Raid creation and signup area with raid size targets, player specs, Tank/Healer/DPS roles, attendance, and signup notes. The GM can check players for the invite roster; selections are shared with the guild.
- PvP leaderboard with outdoor kills, deaths, seasons, and a Most Wanted list.
- Looking For group board; posts expire after three hours.
- Crafting request board; requests expire after seven days and can be claimed by crafters.
- Officer polls with public totals; voter names are not shown in the interface.
- Shoutouts between guild members.
- Pop-up notifications for new guild announcements and events, stacking PvP rewards, and guild-wide level/profession milestones for members running Guild Hall.

Officers (guild leader and rank 1) can create announcements, schedule raids and events, edit the guide, create or close polls, and start PvP seasons. Any guild member can edit their own profile, RSVP, vote, make or claim board requests, and post shoutouts.

Guild data syncs between members running Guild Hall using in-game addon messages. There is no external server. Offline members catch up from an online rank 0 or rank 1 member when they sync. Board requests expire automatically.

In Events, officers use Create raid to schedule a raid and set its signup lock and size target. Creation defaults to also creating an in-game guild-calendar signup event; choose Guild Hall only to skip it. The creator can retry with Create calendar if the client cannot create the calendar copy. Calendar writes require the client's guild-calendar APIs and game permissions.

Members use Sign up / Change to choose Going, Maybe, or Absent, write their spec, choose Tank/Healer/DPS, and add an optional note. Class is detected automatically from the guild roster; player and class columns use class colors. Role totals count Going players only, with older signups missing a role counted as Unassigned. Members can change an existing signup even when new signups are locked, or use Remove my signup to withdraw. The GM can remove anyone's signup. Removal records are synced to prevent older history from restoring a withdrawn signup; members can sign up again while signups are open.

Only the GM can change the invite checkmarks, and only Going players can be selected. Checkmarks record the planned invite list and do not automatically invite players. All participating members should update Guild Hall to exchange the expanded signup data, removals, and GM selections. Raid size is a planning target, so additional members can still sign up. Withdrawing your own signup attempts to decline the matching native calendar event; GM removal affects the Guild Hall roster.

The roster shows online guild members only. Guild Hall clients announce their installed version at login and once per minute; a member with no recent announcement is shown as "No addon detected." This detection requires a client version that sends presence announcements, so older addon versions may not report.

PvP rankings use total eligible kills, regardless of victim level. Each kill counts equally; existing kill totals are preserved and historical level-based points no longer affect rankings. Only game-credited open-world kills count; battlegrounds, arenas, dungeons, raids, and scenarios are excluded. Honor messages and kill-credit updates are combined to avoid counting the same reward twice. Counter-only credits require one identifiable recent enemy death. Victim levels come from recently visible enemy players; unknown levels use your level, and skull-level enemies use your level plus 10, capped at 60. The same victim counts once per five minutes and at most five times per rolling 24 hours. The detailed activity feed keeps up to 60 recent kills and deaths per guild. Leaderboard kill, point, and death totals are cumulative per member and season, synced separately from that feed. Existing saved recent records are folded into a member's totals the next time they record a PvP event; older records already discarded by the 60-entry cap cannot be recovered. A new season starts fresh at its start time.

## Install for development

Copy this folder into the client's `Interface/AddOns` directory, enable **Guild Hall** on the AddOns screen, and join a guild.

## Commands

- `/gh` opens Guild Hall; `/gh sync` requests recent guild data.
- `/gh post Message text` posts an announcement (officer).
- `/gh event YYYY-MM-DD HH:MM | Title | Details` schedules an event (officer).
- `/gh raid YYYY-MM-DD HH:MM | Title | Details` schedules a raid (officer).
- `/gh rsvp # going|tentative|absent` responds to an upcoming calendar entry.
- `/gh profile set Role | Spec | Time zone | Alts | Professions` sets your member profile.
- `/gh profile Name` views a member profile; `/gh profile list` returns to the directory.
- `/gh guide` opens the guild guide; `/gh guide set Rules | Loot rules` updates it (officer).
- `/gh looking Role | Activity | Details` posts a group request; `/gh looking close #` closes your post.
- `/gh craft request Item | Details` posts a crafting request.
- `/gh craft claim #` claims a request; `/gh craft done #` closes it.
- `/gh craft who Recipe` searches online members' listed crafting skills.
- `/gh poll create Question | Option 1 | Option 2 [| Option 3 | Option 4]` creates a poll (officer).
- `/gh poll vote # option#` votes; `/gh poll close #` closes a poll (officer).
- PvP → New season creates a PvP season (guild master only), with an end date in DD-MM-YYYY format. The end date includes that entire day in the creator's local time. The New season button offers the same fields. When the deadline passes, new kills count toward all-time stats only; the finished season remains visible. All members must update for the cutoff to apply consistently.
- `/gh pvp wipe CONFIRM` permanently clears all guild PvP points, kills, deaths, recent records, and seasons (guild master / rank 0 only). The saved reset syncs to updated members, including members who return later; older clients must update to honor resets. Repeat-victim history clears when a client receives the reset.
- `/gh shout Player Name | Message` posts a shoutout.
- `/gh map waypoint CharacterName` sets a waypoint to a member's latest shared location; `/gh map clear` clears it.
- `/gh popout pvp`, `/gh popout level10` (also 20/30/40/50/60), or `/gh popout profession150` (also 225/300) previews a popout locally.
- `/gh testpopout level` or `/gh testpopout profession` sends a milestone popup test to online Guild Hall users (guild leader/rank 1).

Personal Settings can turn Guild Hall popups on or off, optionally share your map location with Guild Hall members, and optionally send a guild-chat “Ding!” for level milestones. Map sharing is off by default, pauses in instances, and reports expire after 45 seconds. Profession milestones never send guild chat messages.

Date and time in event commands use the local time shown by the game client. Board item numbers refer to the current order shown in their tab.

## Project layout

- `Core/Runtime.lua` provides addon lifecycle, saved data, slash routing, and guild message sync.
- `Features/` contains independent modules for profiles, announcements, events, shoutouts, PvP, guild guide, group requests, crafting, and polls.
- `UI/Main.lua` builds the shared window, navigation, and roster view.
- `GuildHall.toc` lists the files in WoW load order.
