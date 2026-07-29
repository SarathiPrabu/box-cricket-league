# Box Cricket League — Codex Instructions

## Project Goal

Build and maintain a free-to-host web application for managing box cricket leagues.

The application must support:

* Multiple independent leagues
* Multiple seasons within each league
* Multiple teams within each league
* Players participating in multiple leagues
* Players changing teams between seasons
* Historical player, team, match, batting, bowling, fielding, and auction records

A player's identity is independent of a league, season, or team.

A league contains multiple seasons.

Teams belong to a league.

A player's team assignment belongs to a specific season through a season roster.

The same player may participate in multiple leagues and may represent different teams in different seasons.

Historical records must never be changed when a player joins another team, season, or league.

All league-specific administrative data must be isolated by league. Users who administer one league must not automatically have permission to modify another league.

The architecture should support future player-level career statistics at three levels:

* Overall career across all leagues
* Career within a specific league
* Statistics within a specific season


## Technology

Frontend:

* React
* TypeScript
* Vite
* Tailwind CSS
* React Router

Backend platform:

* Supabase
* PostgreSQL
* Supabase Auth
* Supabase Storage when needed
* Supabase Realtime only when needed

Hosting:

* Cloudflare Pages

Do not introduce a custom backend unless there is a demonstrated requirement that Supabase cannot reasonably handle.

## Architecture Principles

Keep the architecture simple.

Do not introduce:

* Microservices
* CQRS
* MediatR
* Message brokers
* Redis
* Kubernetes
* Separate backend APIs
* Unnecessary abstractions
* Repository patterns around Supabase without a clear reason

Prefer the simplest implementation that is maintainable.

Database integrity is more important than frontend convenience.

## Core Domain Model

Permanent entities:

* players
* teams

Season-dependent entities:

* seasons
* season_teams
* season_rosters

Match entities:

* matches
* match_player_stats

A player must not have a permanent team assignment in the players table.

Player-to-team relationships belong to a season roster.

Historical Season 1 data must never change when a player joins another team in Season 2.

## Statistics

match_player_stats is the source of truth for cricket statistics.

Store raw match data such as:

* runs
* balls_faced
* fours
* sixes
* balls_bowled
* runs_conceded
* wickets
* catches
* stumpings
* player-of-the-match

Do not manually maintain duplicated career totals.

Season and career statistics should be derived using PostgreSQL queries/views.

Player profiles must support:

* Career
* Season 1
* Season 2
* Future seasons
* Match-by-match history

## Development Rules

Before making a substantial change:

1. Inspect the existing implementation.
2. Explain the proposed change briefly.
3. Identify affected files and database objects.
4. Preserve existing working behaviour unless explicitly asked to change it.
5. Implement the smallest useful change.
6. Run relevant tests and checks.
7. Report what changed and anything that remains unresolved.

Do not rewrite working code merely for stylistic reasons.

Do not add dependencies without explaining why they are necessary.

Prefer TypeScript strict typing.

Avoid `any` unless unavoidable and documented.

Keep React components reasonably small.

Keep database migrations version-controlled under `supabase/migrations`.

Never modify an old production migration to change database history. Add a new migration.

Never commit:

* API keys
* Supabase service-role keys
* passwords
* secrets
* production credentials

Use environment variables and maintain `.env.example`.

## UI

Design primarily for mobile because league participants are likely to access the site from phones.

Public pages should load without authentication.

Admin functionality requires authentication.

Keep the design clean and sports-oriented without sacrificing readability.

## Testing

For every significant feature:

* run TypeScript checks
* run linting
* run relevant tests
* build the production frontend

For database changes:

* verify constraints
* verify foreign keys
* verify Row Level Security policies
* test representative queries

## Git

Keep changes focused.

Do not mix unrelated refactoring with feature implementation.

Before finishing a task, summarize:

* files changed
* database changes
* tests/checks performed
* assumptions
* remaining risks

## Current Priority

Ship a usable MVP.
Prefer completed features over architectural sophistication.
