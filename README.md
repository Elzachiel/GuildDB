# Guild Hall

Guild Hall is a World of Warcraft guild addon for a shared roster, member profiles, announcements, raids, events, shoutouts, and guild utilities. It is designed to work independently for any guild.

## Features

- Online-only guild roster with Guild Hall presence and reported addon version.
- Opt-in guild member location sharing with fresh reports, World Map pins, and waypoint navigation.
- Member profiles for role, specialization, time zone, alts, and listed professions or recipes.
- Officer announcements and a guild guide for rules and loot rules.
- Raid and event calendar with Going, Tentative, and Absent RSVPs.
- PvP leaderboard with outdoor kills, deaths, seasons, and a Most Wanted list.
- Looking For group board; posts expire after three hours.
- Crafting request board; requests expire after seven days and can be claimed by crafters.
- Officer polls with public totals; voter names are not shown in the interface.
- Shoutouts between guild members.
- Pop-up notifications for new guild announcements and events, stacking PvP rewards, and guild-wide level/profession milestones for members running Guild Hall.

Officers (guild leader and rank 1) can create announcements, schedule raids and events, edit the guide, create or close polls, and start PvP seasons. Any guild member can edit their own profile, RSVP, vote, make or claim board requests, and post shoutouts.

Guild data syncs between members running Guild Hall using in-game addon messages. There is no external server. Offline members catch up from an online rank 0 or rank 1 member when they sync. Board requests expire automatically.

The roster shows online guild members only. Guild Hall clients announce their installed version at login and once per minute; a member with no recent announcement is shown as "No addon detected." This detection requires a client version that sends presence announcements, so older addon versions may not report.

PvP points are based on victim level: levels 1-19 earn 1 point, 20-29 earn 2, 30-39 earn 3, 40-49 earn 4, and 50+ earn 5. Only game-credited open-world kills count; battlegrounds, arenas, dungeons, raids, and scenarios are excluded. Honor messages and kill-credit updates are combined to avoid counting the same reward twice. Counter-only credits require one identifiable recent enemy death. Victim levels come from recently visible enemy players; unknown levels use your level, and skull-level enemies use your level plus 10, capped at 60. The same victim counts once per five minutes and at most five times per rolling 24 hours. The detailed activity feed keeps up to 60 recent kills and deaths per guild. Leaderboard kill, point, and death totals are cumulative per member and season, synced separately from that feed. Existing saved recent records are folded into a member's totals the next time they record a PvP event; older records already discarded by the 60-entry cap cannot be recovered. A new season starts fresh at its start time.

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
- `/gh pvp season Season name` starts a PvP season (officer).
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
