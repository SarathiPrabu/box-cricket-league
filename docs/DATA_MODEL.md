# Data Model

## Goals

The data model must support:

- Multiple leagues.
- Multiple seasons per league.
- Teams that belong to a league.
- Players who can participate in multiple leagues.
- Players changing teams between seasons.
- Historical match and player statistics that do not change when future rosters change.
- Match lineups, including the captain selected for each team.
- Match officials, commentators, and video links.
- League-level administration and future moderator roles.
- Future auctions without changing the core season roster model.

For MVP, build for one league in the UI, but keep `leagues` in the database from the beginning.

## Core Rule

A player is not the same thing as a team.

A player does not have a permanent team assignment.

Player team assignment belongs to a season roster:

```text
player + season_team -> season_roster
```

Historical records must point to the roster/team context that existed when the match was played.

## MVP Tables

```text
leagues
league_members
players
teams
seasons
season_teams
season_team_managers
season_rosters
matches
match_staff
match_lineups
match_player_stats
```

## Relationships

```text
league -> seasons
league -> teams
league -> league_members

season -> season_teams
team -> season_teams

season_team -> season_team_managers
player -> season_team_managers

season_team -> season_rosters
player -> season_rosters

season -> matches
season_team -> matches

match -> match_staff
season_roster -> match_staff

match -> match_lineups
season_team -> match_lineups
season_roster -> match_lineups

match -> match_player_stats
match_lineup -> match_player_stats
```

## Table Notes

### leagues

Represents an independent box cricket league.

Suggested fields:

```text
id
name
slug
description
created_at
updated_at
```

Each league should eventually have its own home page.

For MVP, the application may show only one league, but all league-specific data should still reference `league_id`.

### league_members

Represents authenticated users who can manage a league.

Suggested fields:

```text
id
league_id
user_id
role
created_at
```

Allowed roles:

```text
admin
scorer
player
team_manager
```

For MVP, `admin` manages league setup and permissions, `scorer` manages match scoring data, `team_manager` can manage their assigned team lineups, and `player` is the authenticated player-facing role.

This table replaces a narrow `league_admins` table.

Bootstrap note:

The first league admin cannot be created through normal admin-only app permissions, because no admin exists yet. For MVP, create the first authenticated user in Supabase Auth, then insert the first `league_members` row through the Supabase SQL editor, a controlled seed, or another service-role-only setup step.

After the first admin exists, league membership should be managed through normal authenticated admin flows.

### players

Represents a person/player globally.

Suggested fields:

```text
id
display_name
full_name
created_at
updated_at
```

Rules:

- Do not store `team_id` on `players`.
- Do not store league-specific stats on `players`.
- A player can appear in multiple leagues through season rosters.

### teams

Represents a team owned by a league.

Suggested fields:

```text
id
league_id
name
slug
created_at
updated_at
```

Rules:

- A team belongs to one league.
- A team can participate in multiple seasons through `season_teams`.

### seasons

Represents a league season.

Suggested fields:

```text
id
league_id
name
starts_on
ends_on
players_per_team
created_at
updated_at
```

Rules:

- A season belongs to one league.
- Player-team assignments are season-specific.
- `players_per_team` is decided by the league admin before the season starts.
- Match lineups should use exactly this number of players per team.

### season_teams

Represents a team participating in a specific season.

Suggested fields:

```text
id
season_id
team_id
created_at
```

Rules:

- A team should only appear once per season.
- Matches should reference `season_teams`, not plain `teams`.

Recommended constraint:

```text
unique(season_id, team_id)
```

### season_team_managers

Represents managers for a team in a specific season.

Suggested fields:

```text
id
season_team_id
player_id nullable
user_id nullable
display_name
created_at
```

Rules:

- Managers belong to a season team, not permanently to a team.
- A manager may also be a player.
- A manager may not play.
- `player_id` is optional because not every manager must be in the player pool.
- `user_id` is optional until manager login/permissions are implemented.

### season_rosters

Represents a player assigned to a team for a season.

Suggested fields:

```text
id
season_team_id
season_id
player_id
created_at
```

Rules:

- This is the source of truth for which team a player represented in a season.
- A player should not be assigned to two teams in the same season.
- If a player changes teams next season, create a new season roster row.
- Do not update historical roster rows to reflect future team changes.

Recommended constraints:

```text
unique(season_team_id, player_id)
unique(season_id, player_id)
```

Implementation note:

`unique(season_id, player_id)` requires either storing `season_id` directly on `season_rosters` or enforcing the rule through a database trigger/function using `season_team_id`.

For MVP, storing `season_id` directly on `season_rosters` is acceptable if a foreign key or trigger ensures it matches the `season_team`.

The duplicate `season_id` is intentional for MVP. It allows a simple database uniqueness rule, `unique(season_id, player_id)`, so one player cannot accidentally belong to two teams in the same season. The migration must still validate that `season_rosters.season_id` matches the season from `season_rosters.season_team_id`.

### matches

Represents a match within a season.

Suggested fields:

```text
id
season_id
home_season_team_id
away_season_team_id
match_date
venue
status
youtube_url nullable
winner_season_team_id nullable
created_at
updated_at
```

Rules:

- A match belongs to one season.
- Match teams must be season teams from the same season.
- Do not reference plain `teams` from matches.
- `youtube_url` can store a live stream or recorded match link.

Suggested statuses:

```text
scheduled
completed
cancelled
```

### match_staff

Represents non-playing match roles such as umpire and commentator.

Match officials must be players, but they must not be selected in either team's playing lineup for that match.

Suggested fields:

```text
id
match_id
role
season_roster_id
user_id nullable
created_at
```

Allowed roles:

```text
umpire
commentator
```

Rules:

- A match may have one or more umpires.
- A match may have zero or more commentators.
- Staff must reference a player through `season_roster_id`.
- Staff must belong to the same season as the match.
- Staff must not appear in `match_lineups` for the same match.
- Staff may be linked to a user if login/permissions are needed later.
- Match staff are not part of the playing team for that match.

Recommended constraints:

```text
unique(match_id, role, season_roster_id)
```

Implementation note:

The rules that a match official belongs to the same season and cannot also be in the match lineup should be enforced with a database trigger or validation function. The UI should also hide players already selected in either team's lineup when choosing officials.

### match_lineups

Represents the players selected by a team manager for a specific match.

Suggested fields:

```text
id
match_id
season_team_id
season_roster_id
is_captain
selected_by_user_id nullable
created_at
updated_at
```

Rules:

- A lineup row must reference a player from that team's season roster.
- `season_team_id` must be either the home or away season team for the match.
- `season_roster_id` must belong to the same `season_team_id` on the lineup row.
- Incomplete lineups are allowed while a match is being prepared.
- A completed match must have at least one lineup player for each team.
- A completed match must have exactly one captain for each team.
- The captain must be one of the selected lineup players.
- A manager can select himself as captain only if he is also in that team's `season_rosters` and selected in the lineup.
- Match stats should only be entered for players in the match lineup.

Recommended constraints:

```text
unique(match_id, season_roster_id)
```

Implementation note:

The "lineup team is playing this match", "roster belongs to lineup team", "at least one player per team before completion", and "exactly one captain per team before completion" rules are best enforced with database triggers or validation functions. The UI should also validate them before saving.

### match_player_stats

Source of truth for player match statistics.

Suggested fields:

```text
id
match_lineup_id
runs
balls_faced
fours
sixes
balls_bowled
runs_conceded
wickets
catches
stumpings
is_player_of_match
created_at
updated_at
```

Rules:

- Store raw match stats only.
- Do not manually store duplicated career totals.
- Derived statistics should come from PostgreSQL views or queries.
- `match_lineup_id` is the main reference for the match, player, roster, and team context.
- The match is derived through `match_lineups.match_id`.
- The player is derived through `match_lineups.season_roster_id -> season_rosters.player_id`.
- The team is derived through `match_lineups.season_team_id`.
- A completed match must have exactly one player of the match.
- Player-of-the-match corrections should be done with an atomic database helper so the app does not temporarily save two winners.

## Statistics

`match_player_stats` is the source of truth.

Derived views can support:

```text
season batting leaderboard
season bowling leaderboard
player season stats
player league career stats
player overall career stats
match-by-match player history
```

Do not maintain career totals by updating columns after each match.

## Access Control

League data is private by default.

For now, do not add a league visibility setting.

Access should be based on `league_members`:

```text
admin -> manage league data
scorer -> manage match scoring data
team_manager -> manage assigned team lineups
player -> authenticated player-facing access
```

Public league pages can be added later as a separate feature.

## Future Auction Tables

Do not build auction tables for the first MVP unless auction entry becomes an immediate requirement.

When needed, add auction-specific tables that feed into `season_rosters`.

Potential future tables:

```text
auctions
auction_players
auction_team_budgets
auction_bids
```

Auction flow:

```text
league admin creates auction
league admin sets team points
players opt in or opt out
teams bid on players
completed auction creates season_rosters
```

Important rule:

Auction results should create roster rows. They should not replace `season_rosters` as the source of truth.
