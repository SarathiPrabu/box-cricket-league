# Architecture

## MVP Stack

```text
React + TypeScript + Vite + Tailwind CSS
        |
        v
Supabase JS client
        |
        v
Supabase Auth + PostgreSQL + Row Level Security
        |
        v
Supabase Realtime for live match scoring
```

Frontend hosting:

```text
Cloudflare Pages
```

## Core Decisions

- The app is a static React frontend hosted on Cloudflare Pages.
- The frontend talks directly to Supabase using the Supabase JS client.
- Supabase Auth handles authentication.
- PostgreSQL is the source of truth for league, season, team, player, match, lineup, and score data.
- Row Level Security controls who can read and write league data.
- League data is private by default.
- Supabase Realtime is used for live match scoring updates.
- Career, season, leaderboard, and player profile statistics are derived from PostgreSQL queries or views.

## Live Scoring

Live scoring should work by writing score changes to PostgreSQL first.

Supabase Realtime then broadcasts database changes to subscribed match pages.

Initial realtime scope:

```text
matches
match_lineups
match_innings
match_batting_turns
match_over_assignments
match_deliveries
match_player_stats
```

Rules:

- Realtime does not replace PostgreSQL as the source of truth.
- Only authenticated league admins or allowed future roles can write scores.
- Viewers receive live updates by subscribing to the current match data.
- Keep realtime limited to match pages until another feature clearly needs it.

Delivery events are the live scoring source of truth. `match_batting_turns` controls which selected batsman may face each delivery and allows a six-legal-ball batting turn to cross bowling-over boundaries. Completed-match player aggregates are materialized into `match_player_stats` in the same finalization transaction that sets the result. Final innings team totals, including extras, are persisted separately on `match_innings` for standings and NRR.

The current over remains editable after its sixth legal ball. The scorer explicitly confirms it before the database locks its deliveries and allows the next over to begin.

The scorer route and live-scoring RPCs are temporarily public for review. Role-based protection must be restored before production use.

## Data Integrity

Database integrity is more important than frontend convenience.

PostgreSQL should enforce core rules where practical:

- A player does not have a permanent team.
- A player's team assignment belongs to a season roster.
- Match lineups only include players from teams playing that match.
- Each match team has exactly one captain.
- Match officials are players from the season but are not in the playing lineup.
- Match statistics belong to selected match lineup players.

## MVP Exclusions

Do not add these for MVP:

- Custom backend API.
- Microservices.
- Message broker.
- Redis.
- Separate websocket server.
- Supabase Storage, unless uploads become necessary.
- Broad app-wide realtime subscriptions.

## Future Additions

Add later only when the feature needs it:

- Supabase Storage for team logos, player photos, or league assets.
- Public league sharing.
- Player-to-login mapping for player-specific pre-match lineup visibility.
- Auction opt-in and bidding.
