import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import https from 'node:https';

const DOC_NAMES = [
  'season1Standings',
  'season1Leaderboard',
  'season1Auction',
  'season1Matches',
];

const REPO_ROOT = resolve(fileURLToPath(new URL('..', import.meta.url)));
const OUTPUT_DIR = join(REPO_ROOT, 'supabase', 'seed-data');
const SEED_SQL_PATH = join(REPO_ROOT, 'supabase', 'seed.sql');
const SOURCE_JSON_PATH = join(OUTPUT_DIR, 'season1-source.json');
const REPORT_JSON_PATH = join(OUTPUT_DIR, 'season1-import-report.json');

const LEAGUE = {
  id: stableUuid('league:box-cricket-league'),
  name: 'Box Cricket League',
  slug: 'box-cricket-league',
};

const SEASON = {
  id: stableUuid('season:box-cricket-league:season1'),
  name: 'Season 1',
};

const SOURCE_PLAYER_NAME_CORRECTIONS = new Map([
  ['WcAFWjDOY4kKqJr2iBDW', 'Mahesh Kshatriya'],
]);

function usage() {
  console.error('Usage: npm run seed:season1:generate -- <path-to-har> [--archive-dir <path-with-firestore-json>]');
  process.exit(1);
}

function parseArgs(argv) {
  const args = [...argv];
  const harPath = args.shift();
  if (!harPath) usage();

  let archiveDir = process.env.SEASON1_ARCHIVE_DIR || null;
  while (args.length > 0) {
    const arg = args.shift();
    if (arg === '--archive-dir') {
      archiveDir = args.shift();
      if (!archiveDir) usage();
    } else {
      usage();
    }
  }

  return {
    harPath: resolve(harPath),
    archiveDir: archiveDir ? resolve(archiveDir) : null,
  };
}

function decodeFirestoreValue(value) {
  if (!value || typeof value !== 'object') return value;
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('nullValue' in value) return null;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decodeFirestoreValue);
  if ('mapValue' in value) {
    return Object.fromEntries(
      Object.entries(value.mapValue.fields || {}).map(([key, nestedValue]) => [
        key,
        decodeFirestoreValue(nestedValue),
      ]),
    );
  }
  return value;
}

function decodeFirestoreDocument(document) {
  return Object.fromEntries(
    Object.entries(document.fields || {}).map(([key, value]) => [key, decodeFirestoreValue(value)]),
  );
}

function extractArchiveDocumentPaths(harPath) {
  const har = JSON.parse(readFileSync(harPath, 'utf8'));
  const paths = new Set();

  for (const entry of har.log?.entries || []) {
    const postText = entry.request?.postData?.text;
    if (!postText) continue;

    const params = new URLSearchParams(postText);
    for (const [key, value] of params.entries()) {
      if (!key.endsWith('___data__')) continue;

      const payload = JSON.parse(value);
      const documents = payload.addTarget?.documents?.documents || [];
      for (const documentPath of documents) {
        if (documentPath.includes('/documents/archive/')) {
          paths.add(documentPath);
        }
      }
    }
  }

  return [...paths].sort();
}

async function fetchJson(url) {
  return new Promise((resolvePromise, rejectPromise) => {
    https
      .get(url, (response) => {
        let body = '';
        response.setEncoding('utf8');
        response.on('data', (chunk) => {
          body += chunk;
        });
        response.on('end', () => {
          if (response.statusCode < 200 || response.statusCode >= 300) {
            rejectPromise(new Error(`GET ${url} failed with ${response.statusCode}: ${body}`));
            return;
          }
          resolvePromise(JSON.parse(body));
        });
      })
      .on('error', rejectPromise);
  });
}

async function loadArchiveDocuments(harPath, archiveDir) {
  const documentPaths = extractArchiveDocumentPaths(harPath);
  const foundNames = documentPaths.map((path) => basename(path));
  const missingNames = DOC_NAMES.filter((name) => !foundNames.includes(name));
  if (missingNames.length > 0) {
    throw new Error(`HAR did not reference required archive documents: ${missingNames.join(', ')}`);
  }

  const documents = {};
  for (const documentPath of documentPaths) {
    const name = basename(documentPath);
    const localPath = archiveDir ? join(archiveDir, `${name}.json`) : null;
    const rawDocument =
      localPath && existsSync(localPath)
        ? JSON.parse(readFileSync(localPath, 'utf8'))
        : await fetchJson(
            `https://firestore.googleapis.com/v1/${documentPath.replace(
              'projects/gully-league/databases/(default)/documents/',
              'projects/gully-league/databases/(default)/documents/',
            )}`,
          );

    documents[name] = {
      name: rawDocument.name,
      createTime: rawDocument.createTime,
      updateTime: rawDocument.updateTime,
      fields: decodeFirestoreDocument(rawDocument),
    };
  }

  return documents;
}

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function stableUuid(key) {
  const hex = createHash('sha256').update(key).digest('hex').slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(
    16,
    20,
  )}-${hex.slice(20, 32)}`;
}

function sqlString(value) {
  if (value === null || value === undefined) return 'null';
  return `'${String(value).replaceAll("'", "''")}'`;
}

function sqlUuid(value) {
  return `${sqlString(value)}::uuid`;
}

function sqlTimestamp(value) {
  return value ? `${sqlString(value)}::timestamptz` : 'null';
}

function uniqBy(values, keyFn) {
  const map = new Map();
  for (const value of values) {
    const key = keyFn(value);
    if (!map.has(key)) map.set(key, value);
  }
  return [...map.values()];
}

function normalizeSourcePlayer(player) {
  if (!player?.playerId) return player;
  const correctedName = SOURCE_PLAYER_NAME_CORRECTIONS.get(player.playerId);
  return correctedName ? { ...player, name: correctedName } : player;
}

function getRequiredNumber(record, field, label, issues) {
  const value = record[field];
  if (typeof value !== 'number' || Number.isNaN(value)) {
    issues.push(`${label} is missing numeric field ${field}`);
    return null;
  }
  return value;
}

function buildSeedModel(source) {
  const standingsRows = source.season1Standings.fields.rows || [];
  const leaderboardPlayers = source.season1Leaderboard.fields.players || [];
  const auctionTeams = source.season1Auction.fields.teams || [];
  const matches = source.season1Matches.fields.matches || [];
  const capturedAt = source.season1Leaderboard.fields.capturedAt || null;
  const auctionTotals = source.season1Auction.fields.totals || {};

  const issues = [];
  const unmapped = [];

  const teamNames = uniqBy(
    [
      ...standingsRows.map((row) => row.teamName),
      ...auctionTeams.map((team) => team.teamName),
      ...leaderboardPlayers.map((player) => player.teamName),
      ...matches.flatMap((match) => [match.teamAName, match.teamBName, match.winnerName]).filter(Boolean),
    ].filter(Boolean),
    (name) => name,
  ).sort((left, right) => left.localeCompare(right));

  const teams = teamNames.map((name) => ({
    id: stableUuid(`team:${LEAGUE.slug}:${name}`),
    name,
    slug: slugify(name),
  }));

  const auctionPlayers = auctionTeams.flatMap((team) =>
    (team.players || []).map((player) => ({
      source: 'auction',
      teamName: team.teamName,
      managerName: team.managerName,
      managerId: team.managerId,
      ...normalizeSourcePlayer(player),
    })),
  );

  const playerRows = [];
  for (const player of auctionPlayers) {
    if (!player.playerId || !player.name) {
      unmapped.push({ type: 'auction_player', reason: 'missing playerId or name', record: player });
      continue;
    }
    playerRows.push(normalizeSourcePlayer(player));
  }

  for (const player of leaderboardPlayers) {
    if (!player.playerId || !player.name) {
      unmapped.push({ type: 'leaderboard_player', reason: 'missing playerId or name', record: player });
      continue;
    }
    playerRows.push(player);
  }

  for (const team of auctionTeams) {
    if (!team.managerId || !team.managerName) {
      unmapped.push({ type: 'team_manager', reason: 'missing managerId or managerName', record: team });
      continue;
    }
    playerRows.push({
      playerId: team.managerId,
      name: SOURCE_PLAYER_NAME_CORRECTIONS.get(team.managerId) || team.managerName,
      teamName: team.teamName,
      source: 'manager',
    });
  }

  const playersBySourceId = new Map();
  for (const player of playerRows) {
    const existing = playersBySourceId.get(player.playerId);
    if (existing && existing.displayName !== player.name) {
      issues.push(
        `source player ${player.playerId} has conflicting names: ${existing.displayName} / ${player.name}`,
      );
    }
    if (!existing) {
      playersBySourceId.set(player.playerId, {
        id: stableUuid(`player:${player.playerId}`),
        sourcePlayerId: player.playerId,
        displayName: player.name,
      });
    }
  }

  const rosterSourceRows = uniqBy(
    [
      ...auctionPlayers.filter((player) => player.playerId && player.teamName),
      ...leaderboardPlayers
        .filter((player) => player.playerId && player.teamName)
        .map(normalizeSourcePlayer),
      ...auctionTeams
        .filter((team) => team.managerId && team.teamName)
        .map((team) => ({
          playerId: team.managerId,
          name: team.managerName,
          teamName: team.teamName,
        })),
    ],
    (player) => player.playerId,
  );

  const seasonTeams = teams.map((team) => ({
    id: stableUuid(`season-team:${SEASON.id}:${team.id}`),
    seasonId: SEASON.id,
    teamId: team.id,
    teamName: team.name,
  }));
  const seasonTeamsByTeamName = new Map(seasonTeams.map((seasonTeam) => [seasonTeam.teamName, seasonTeam]));

  const seasonRosters = [];
  for (const player of rosterSourceRows) {
    const mappedPlayer = playersBySourceId.get(player.playerId);
    const seasonTeam = seasonTeamsByTeamName.get(player.teamName);
    if (!mappedPlayer || !seasonTeam) {
      unmapped.push({
        type: 'season_roster',
        reason: 'player or team could not be mapped',
        record: player,
      });
      continue;
    }
    seasonRosters.push({
      id: stableUuid(`season-roster:${SEASON.id}:${player.playerId}`),
      seasonTeamId: seasonTeam.id,
      seasonId: SEASON.id,
      playerId: mappedPlayer.id,
      sourcePlayerId: player.playerId,
      teamName: player.teamName,
    });
  }

  const rostersBySourcePlayerId = new Map(
    seasonRosters.map((seasonRoster) => [seasonRoster.sourcePlayerId, seasonRoster]),
  );

  const seasonTeamManagers = [];
  for (const team of auctionTeams) {
    const mappedPlayer = team.managerId ? playersBySourceId.get(team.managerId) : null;
    const seasonTeam = seasonTeamsByTeamName.get(team.teamName);
    if (!seasonTeam || !team.managerName) {
      unmapped.push({ type: 'season_team_manager', reason: 'team or manager name could not be mapped', record: team });
      continue;
    }
    seasonTeamManagers.push({
      id: stableUuid(`season-team-manager:${SEASON.id}:${team.teamName}:${team.managerId || team.managerName}`),
      seasonTeamId: seasonTeam.id,
      playerId: mappedPlayer?.id || null,
      displayName: team.managerName,
    });
  }

  const legacyStats = [];
  const leaderboardPlayerIds = new Set();
  for (const player of leaderboardPlayers) {
    leaderboardPlayerIds.add(player.playerId);
    const label = `leaderboard player ${player.playerId || player.name || '<unknown>'}`;
    const mappedPlayer = player.playerId ? playersBySourceId.get(player.playerId) : null;
    if (!mappedPlayer) {
      unmapped.push({ type: 'legacy_season_player_stats', reason: 'player could not be mapped', record: player });
      continue;
    }

    const stat = {
      id: stableUuid(`legacy-season-player-stat:${SEASON.id}:${player.playerId}`),
      seasonId: SEASON.id,
      playerId: mappedPlayer.id,
      seasonRosterId: rostersBySourcePlayerId.get(player.playerId)?.id || null,
      source: 'firestore.archive.season1Leaderboard',
      sourcePlayerId: player.playerId,
      sourceTeamName: player.teamName,
      matchesPlayed: getRequiredNumber(player, 'matchesPlayed', label, issues),
      runs: getRequiredNumber(player, 'runs', label, issues),
      ballsFaced: getRequiredNumber(player, 'ballsFaced', label, issues),
      fours: getRequiredNumber(player, 'fours', label, issues),
      sixes: getRequiredNumber(player, 'sixes', label, issues),
      ballsBowled: getRequiredNumber(player, 'ballsBowled', label, issues),
      runsConceded: getRequiredNumber(player, 'runsConceded', label, issues),
      wickets: getRequiredNumber(player, 'wickets', label, issues),
      catches: getRequiredNumber(player, 'catches', label, issues),
      stumpings: getRequiredNumber(player, 'stumpings', label, issues),
      playerOfMatchCount: getRequiredNumber(player, 'momCount', label, issues),
      totalPoints: getRequiredNumber(player, 'totalPoints', label, issues),
      capturedAt,
    };

    const requiredStatFields = [
      'matchesPlayed',
      'runs',
      'ballsFaced',
      'fours',
      'sixes',
      'ballsBowled',
      'runsConceded',
      'wickets',
      'catches',
      'stumpings',
      'playerOfMatchCount',
      'totalPoints',
    ];

    if (requiredStatFields.some((field) => stat[field] === null)) {
      unmapped.push({ type: 'legacy_season_player_stats', reason: 'required stat field missing', record: player });
      continue;
    }

    legacyStats.push(stat);
  }

  for (const rosterPlayer of rosterSourceRows) {
    if (leaderboardPlayerIds.has(rosterPlayer.playerId)) continue;

    const mappedPlayer = playersBySourceId.get(rosterPlayer.playerId);
    const seasonRoster = rostersBySourcePlayerId.get(rosterPlayer.playerId);
    if (!mappedPlayer || !seasonRoster) {
      unmapped.push({
        type: 'legacy_season_player_stats',
        reason: 'missing leaderboard player could not be mapped to a season roster',
        record: rosterPlayer,
      });
      continue;
    }

    legacyStats.push({
      id: stableUuid(`legacy-season-player-stat:${SEASON.id}:${rosterPlayer.playerId}`),
      seasonId: SEASON.id,
      playerId: mappedPlayer.id,
      seasonRosterId: seasonRoster.id,
      source: 'firestore.archive.season1Leaderboard.missing-defaulted',
      sourcePlayerId: rosterPlayer.playerId,
      sourceTeamName: rosterPlayer.teamName,
      matchesPlayed: 0,
      runs: 0,
      ballsFaced: 0,
      fours: 0,
      sixes: 0,
      ballsBowled: 0,
      runsConceded: 0,
      wickets: 0,
      catches: 0,
      stumpings: 0,
      playerOfMatchCount: 0,
      totalPoints: 0,
      capturedAt,
    });
  }

  const knownPlayerNames = new Map();
  for (const player of playersBySourceId.values()) {
    const names = knownPlayerNames.get(player.displayName) || [];
    names.push(player);
    knownPlayerNames.set(player.displayName, names);
  }

  for (const match of matches) {
    if (!match.momName) continue;
    const candidates = knownPlayerNames.get(match.momName) || [];
    if (candidates.length !== 1) {
      unmapped.push({
        type: 'match_player_of_match',
        reason: candidates.length === 0 ? 'momName did not match any known player' : 'momName matched multiple players',
        record: {
          matchId: match.matchId,
          momName: match.momName,
          teamAName: match.teamAName,
          teamBName: match.teamBName,
        },
      });
    }
  }

  if (standingsRows.length > 0) {
    unmapped.push({
      type: 'season1_standings',
      reason: 'current schema has teams but no standings snapshot table',
      count: standingsRows.length,
    });
  }

  if (matches.length > 0) {
    unmapped.push({
      type: 'season1_matches',
      reason: 'source has match summaries but no lineups or scorecard rows; raw match_player_stats cannot be created without guessing',
      count: matches.length,
    });
  }

  const players = [...playersBySourceId.values()].sort((left, right) =>
    left.displayName.localeCompare(right.displayName),
  );

  return {
    league: LEAGUE,
    season: {
      ...SEASON,
      playersPerTeam: auctionTotals.playerCount && auctionTotals.teamCount
        ? auctionTotals.playerCount / auctionTotals.teamCount
        : null,
    },
    teams,
    players,
    seasonTeams,
    seasonRosters,
    seasonTeamManagers,
    legacyStats,
    sourceCounts: {
      auctionTeams: auctionTeams.length,
      auctionPlayers: auctionPlayers.length,
      leaderboardPlayers: leaderboardPlayers.length,
      standingsRows: standingsRows.length,
      matchSummaries: matches.length,
    },
    unmapped,
    issues,
  };
}

function valuesList(rows, renderRow) {
  return rows.map((row) => `  (${renderRow(row).join(', ')})`).join(',\n');
}

function generateSeedSql(model) {
  const statements = [
    '-- Generated by scripts/generate-season1-seed.mjs. Safe to run repeatedly in development.',
    '-- Source: Firestore archive documents referenced by the supplied Season 1 HAR.',
    'begin;',
    '',
    `insert into public.leagues (id, name, slug, description) values (${sqlUuid(
      model.league.id,
    )}, ${sqlString(model.league.name)}, ${sqlString(model.league.slug)}, null)`,
    'on conflict (id) do update set',
    '  name = excluded.name,',
    '  slug = excluded.slug,',
    '  description = excluded.description;',
    '',
    `insert into public.seasons (id, league_id, name, starts_on, ends_on, players_per_team) values (${sqlUuid(
      model.season.id,
    )}, ${sqlUuid(model.league.id)}, ${sqlString(model.season.name)}, null, null, ${model.season.playersPerTeam})`,
    'on conflict (id) do update set',
    '  league_id = excluded.league_id,',
    '  name = excluded.name,',
    '  starts_on = excluded.starts_on,',
    '  ends_on = excluded.ends_on,',
    '  players_per_team = excluded.players_per_team;',
  ];

  statements.push(
    '',
    `with seed_teams (id, name, slug) as (values\n${valuesList(model.teams, (team) => [
      sqlUuid(team.id),
      sqlString(team.name),
      sqlString(team.slug),
    ])}\n)`,
    'insert into public.teams (id, league_id, name, slug)',
    `select id, ${sqlUuid(model.league.id)}, name, slug from seed_teams`,
    'on conflict (id) do update set',
    '  league_id = excluded.league_id,',
    '  name = excluded.name,',
    '  slug = excluded.slug;',
    '',
    `with seed_players (id, display_name) as (values\n${valuesList(model.players, (player) => [
      sqlUuid(player.id),
      sqlString(player.displayName),
    ])}\n)`,
    'insert into public.players (id, display_name, full_name, created_by)',
    'select id, display_name, null, null from seed_players',
    'on conflict (id) do update set',
    '  display_name = excluded.display_name,',
    '  full_name = excluded.full_name;',
    '',
    `with seed_season_teams (id, season_id, team_id) as (values\n${valuesList(
      model.seasonTeams,
      (seasonTeam) => [sqlUuid(seasonTeam.id), sqlUuid(seasonTeam.seasonId), sqlUuid(seasonTeam.teamId)],
    )}\n)`,
    'insert into public.season_teams (id, season_id, team_id)',
    'select id, season_id, team_id from seed_season_teams',
    'on conflict (id) do update set',
    '  season_id = excluded.season_id,',
    '  team_id = excluded.team_id;',
    '',
    `with seed_season_rosters (id, season_team_id, season_id, player_id) as (values\n${valuesList(
      model.seasonRosters,
      (roster) => [
        sqlUuid(roster.id),
        sqlUuid(roster.seasonTeamId),
        sqlUuid(roster.seasonId),
        sqlUuid(roster.playerId),
      ],
    )}\n)`,
    'insert into public.season_rosters (id, season_team_id, season_id, player_id)',
    'select id, season_team_id, season_id, player_id from seed_season_rosters',
    'on conflict (id) do update set',
    '  season_team_id = excluded.season_team_id,',
    '  season_id = excluded.season_id,',
    '  player_id = excluded.player_id;',
    '',
    `with seed_season_team_managers (id, season_team_id, player_id, display_name) as (values\n${valuesList(
      model.seasonTeamManagers,
      (manager) => [
        sqlUuid(manager.id),
        sqlUuid(manager.seasonTeamId),
        manager.playerId ? sqlUuid(manager.playerId) : 'null',
        sqlString(manager.displayName),
      ],
    )}\n)`,
    'insert into public.season_team_managers (id, season_team_id, player_id, user_id, display_name)',
    'select id, season_team_id, player_id, null, display_name from seed_season_team_managers',
    'on conflict (id) do update set',
    '  season_team_id = excluded.season_team_id,',
    '  player_id = excluded.player_id,',
    '  display_name = excluded.display_name;',
    '',
    `with seed_legacy_stats (
  id,
  season_id,
  player_id,
  season_roster_id,
  source,
  source_player_id,
  source_team_name,
  matches_played,
  runs,
  balls_faced,
  fours,
  sixes,
  balls_bowled,
  runs_conceded,
  wickets,
  catches,
  stumpings,
  player_of_match_count,
  total_points,
  captured_at
) as (values\n${valuesList(model.legacyStats, (stat) => [
      sqlUuid(stat.id),
      sqlUuid(stat.seasonId),
      sqlUuid(stat.playerId),
      stat.seasonRosterId ? sqlUuid(stat.seasonRosterId) : 'null',
      sqlString(stat.source),
      sqlString(stat.sourcePlayerId),
      sqlString(stat.sourceTeamName),
      stat.matchesPlayed,
      stat.runs,
      stat.ballsFaced,
      stat.fours,
      stat.sixes,
      stat.ballsBowled,
      stat.runsConceded,
      stat.wickets,
      stat.catches,
      stat.stumpings,
      stat.playerOfMatchCount,
      stat.totalPoints,
      sqlTimestamp(stat.capturedAt),
    ])}\n)`,
    'insert into public.legacy_season_player_stats (',
    '  id, season_id, player_id, season_roster_id, source, source_player_id, source_team_name,',
    '  matches_played, runs, balls_faced, fours, sixes, balls_bowled, runs_conceded,',
    '  wickets, catches, stumpings, player_of_match_count, total_points, captured_at',
    ')',
    'select * from seed_legacy_stats',
    'on conflict (season_id, source, source_player_id) do update set',
    '  player_id = excluded.player_id,',
    '  season_roster_id = excluded.season_roster_id,',
    '  source_team_name = excluded.source_team_name,',
    '  matches_played = excluded.matches_played,',
    '  runs = excluded.runs,',
    '  balls_faced = excluded.balls_faced,',
    '  fours = excluded.fours,',
    '  sixes = excluded.sixes,',
    '  balls_bowled = excluded.balls_bowled,',
    '  runs_conceded = excluded.runs_conceded,',
    '  wickets = excluded.wickets,',
    '  catches = excluded.catches,',
    '  stumpings = excluded.stumpings,',
    '  player_of_match_count = excluded.player_of_match_count,',
    '  total_points = excluded.total_points,',
    '  captured_at = excluded.captured_at;',
    '',
    'commit;',
    '',
  );

  return `${statements.join('\n')}\n`;
}

function buildVerificationSamples(model) {
  const sorted = [...model.legacyStats].sort((left, right) =>
    `${left.sourceTeamName}:${left.sourcePlayerId}`.localeCompare(`${right.sourceTeamName}:${right.sourcePlayerId}`),
  );
  const sampleIndexes = seededSampleIndexes(sorted.length, 5);
  return sampleIndexes.map((index) => {
    const stat = sorted[index];
    const player = model.players.find((candidate) => candidate.id === stat.playerId);
    return {
      playerName: player?.displayName,
      sourcePlayerId: stat.sourcePlayerId,
      teamName: stat.sourceTeamName,
      matchesPlayed: stat.matchesPlayed,
      runs: stat.runs,
      ballsFaced: stat.ballsFaced,
      fours: stat.fours,
      sixes: stat.sixes,
      ballsBowled: stat.ballsBowled,
      runsConceded: stat.runsConceded,
      wickets: stat.wickets,
      catches: stat.catches,
      stumpings: stat.stumpings,
      playerOfMatchCount: stat.playerOfMatchCount,
      totalPoints: stat.totalPoints,
    };
  });
}

function seededSampleIndexes(length, count) {
  const indexes = new Set();
  let seed = 20260729;
  while (indexes.size < Math.min(length, count)) {
    seed = (seed * 1664525 + 1013904223) % 4294967296;
    indexes.add(seed % length);
  }
  return [...indexes].sort((left, right) => left - right);
}

const { harPath, archiveDir } = parseArgs(process.argv.slice(2));
const source = await loadArchiveDocuments(harPath, archiveDir);
const model = buildSeedModel(source);

mkdirSync(OUTPUT_DIR, { recursive: true });
writeFileSync(SOURCE_JSON_PATH, `${JSON.stringify(source, null, 2)}\n`);
writeFileSync(SEED_SQL_PATH, generateSeedSql(model));

const report = {
  generatedAt: new Date().toISOString(),
  harPath,
  archiveDir,
  sourceCounts: model.sourceCounts,
  mappedCounts: {
    leagues: 1,
    seasons: 1,
    teams: model.teams.length,
    players: model.players.length,
    seasonTeams: model.seasonTeams.length,
    seasonRosters: model.seasonRosters.length,
    seasonTeamManagers: model.seasonTeamManagers.length,
    legacySeasonPlayerStats: model.legacyStats.length,
  },
  unmapped: model.unmapped,
  issues: model.issues,
  verificationSamples: buildVerificationSamples(model),
};
writeFileSync(REPORT_JSON_PATH, `${JSON.stringify(report, null, 2)}\n`);

console.log('Season 1 seed generated.');
console.log(`Source: ${SOURCE_JSON_PATH}`);
console.log(`Seed SQL: ${SEED_SQL_PATH}`);
console.log(`Report: ${REPORT_JSON_PATH}`);
console.log('Mapped counts:', report.mappedCounts);
console.log('Unmapped records:', report.unmapped.length);
console.log('Issues:', report.issues.length);
console.log('Verification samples:');
for (const sample of report.verificationSamples) {
  console.log(
    `- ${sample.playerName} (${sample.teamName}): ${sample.runs} runs, ${sample.wickets} wickets, ${sample.totalPoints} points`,
  );
}
