# MVP Roadmap

## Phase 1: Project Foundation

- [x] Architecture decided
- [ ] Project scaffold
- [ ] Tailwind CSS setup
- [ ] React Router setup
- [ ] Supabase client setup
- [ ] Environment variable example

## Phase 2: Supabase Foundation

- [ ] Supabase local setup
- [ ] Initial database migration
- [ ] Row Level Security baseline
- [ ] Seed Season 1 data

Schema order:

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

Important:

- Create `match_lineups` before `match_player_stats`.
- `match_player_stats` should reference `match_lineups`.
- League data is private by default.

## Phase 3: League MVP Pages

- [ ] League home page
- [ ] Season selector
- [ ] Teams list
- [ ] Team detail with season roster
- [ ] Players list
- [ ] Player profile

## Phase 4: Matches

- [ ] Match list
- [ ] Match detail
- [ ] Match staff display
- [ ] Match video link display
- [ ] Match lineups
- [ ] Match captain display
- [ ] Match statistics display

## Phase 5: Leaderboards

- [ ] Batting leaderboard
- [ ] Bowling leaderboard
- [ ] Player match history
- [ ] Player season stats

## Phase 6: Admin MVP

- [ ] Admin authentication
- [ ] League admin authorization
- [ ] Team and player management
- [ ] Season roster management
- [ ] Match setup
- [ ] Match staff and video link setup
- [ ] Match lineup entry
- [ ] Score entry

## Phase 7: Deployment

- [ ] Production Supabase project setup
- [ ] Cloudflare Pages deployment
- [ ] Production environment variables
- [ ] Smoke test deployed app
