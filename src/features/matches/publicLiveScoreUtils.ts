import type {
  MatchScoringState,
  RecordedDismissalType,
  ScoringDelivery,
  ScoringInnings,
  ScoringLineup,
} from './liveMatchTypes';

export type DeliveryContext = {
  delivery: ScoringDelivery;
  overNumber: number;
  ballLabel: string;
  bowlerName: string;
  legalBallsAfter: number;
};

export type BatterScore = {
  playerId: string;
  name: string;
  isCaptain: boolean;
  isCurrent: boolean;
  runs: number;
  balls: number;
  fours: number;
  sixes: number;
  strikeRate: number;
  dismissal: string;
};

export type BowlerScore = {
  playerId: string;
  name: string;
  legalBalls: number;
  maidens: number;
  runs: number;
  wickets: number;
  economy: number;
};

export type FallOfWicket = {
  wicketNumber: number;
  score: number;
  playerName: string;
  over: string;
};

export type CommentaryItem = {
  id: string;
  batterId: string;
  overNumber: number;
  ballLabel: string;
  badge: string;
  runs: number;
  tone: 'default' | 'boundary' | 'wicket';
  description: string;
};

export function getPlayerName(lineups: ScoringLineup[], playerId: string | null) {
  if (!playerId) return 'Unknown player';
  return lineups.find((player) => player.season_roster_id === playerId)?.player_name ?? 'Unknown player';
}

export function getTeamName(state: MatchScoringState, seasonTeamId: string) {
  return seasonTeamId === state.match.home_season_team_id
    ? state.match.home_team_name
    : state.match.away_team_name;
}

export function formatOvers(legalBalls: number, ballsPerOver: number) {
  if (ballsPerOver < 1) return '0.0';
  return `${Math.floor(legalBalls / ballsPerOver)}.${legalBalls % ballsPerOver}`;
}

export function flattenDeliveries(innings: ScoringInnings): DeliveryContext[] {
  let totalLegalBalls = 0;
  const deliveries: DeliveryContext[] = [];

  [...innings.overs]
    .sort((first, second) => first.over_number - second.over_number)
    .forEach((over) => {
      let legalBallsInOver = 0;

      [...over.deliveries]
        .sort((first, second) => first.delivery_sequence - second.delivery_sequence)
        .forEach((delivery) => {
          if (delivery.delivery_type === 'legal') {
            legalBallsInOver += 1;
            totalLegalBalls += 1;
          }

          const displayedBall = delivery.delivery_type === 'legal'
            ? legalBallsInOver
            : legalBallsInOver + 1;

          deliveries.push({
            delivery,
            overNumber: over.over_number,
            ballLabel: `${Math.max(over.over_number - 1, 0)}.${displayedBall}`,
            bowlerName: over.bowler_name,
            legalBallsAfter: totalLegalBalls,
          });
        });
    });

  return deliveries;
}

export function getInningsTotals(innings: ScoringInnings) {
  const deliveries = flattenDeliveries(innings);
  const dismissedPlayers = new Set(
    deliveries
      .map(({ delivery }) => delivery.dismissed_season_roster_id)
      .filter((playerId): playerId is string => Boolean(playerId)),
  );

  return {
    runs: deliveries.reduce(
      (total, { delivery }) => total + delivery.batter_runs + delivery.extra_runs,
      0,
    ),
    wickets: dismissedPlayers.size,
    legalBalls: deliveries.filter(({ delivery }) => delivery.delivery_type === 'legal').length,
  };
}

function dismissalDescription(
  dismissalType: RecordedDismissalType | null,
  bowlerName: string,
  fielderName: string | null,
) {
  switch (dismissalType) {
    case 'bowled':
      return `b ${bowlerName}`;
    case 'caught':
      return `c ${fielderName ?? 'fielder'} b ${bowlerName}`;
    case 'stumped':
      return `st ${fielderName ?? 'wicketkeeper'} b ${bowlerName}`;
    case 'hit_wicket':
      return `hit wicket b ${bowlerName}`;
    case 'hit_out_of_field':
      return `hit out of field b ${bowlerName}`;
    case 'run_out':
      return fielderName ? `run out (${fielderName})` : 'run out';
    default:
      return 'out';
  }
}

export function getBattingScorecard(
  state: MatchScoringState,
  innings: ScoringInnings,
): BatterScore[] {
  const deliveries = flattenDeliveries(innings);
  const teamPlayers = state.lineups.filter(
    (player) => player.season_team_id === innings.batting_season_team_id,
  );
  const activeBatterIds = new Set(
    innings.batting_turns
      .filter((turn) => turn.status === 'active')
      .map((turn) => turn.batter_season_roster_id),
  );
  const battingOrder = new Map(
    innings.batting_turns.map((turn) => [turn.batter_season_roster_id, turn.turn_number]),
  );

  return teamPlayers
    .map((player, lineupIndex): BatterScore & { order: number } => {
      const playerDeliveries = deliveries.filter(
        ({ delivery }) => delivery.striker_season_roster_id === player.season_roster_id,
      );
      const dismissal = deliveries.find(
        ({ delivery }) => delivery.dismissed_season_roster_id === player.season_roster_id,
      );
      const runs = playerDeliveries.reduce(
        (total, { delivery }) => total + delivery.batter_runs,
        0,
      );
      const balls = playerDeliveries.filter(
        ({ delivery }) => delivery.delivery_type === 'legal',
      ).length;
      const hasAppeared = battingOrder.has(player.season_roster_id) || playerDeliveries.length > 0;

      return {
        playerId: player.season_roster_id,
        name: player.player_name,
        isCaptain: player.is_captain,
        isCurrent: activeBatterIds.has(player.season_roster_id),
        runs,
        balls,
        fours: playerDeliveries.filter(({ delivery }) => delivery.batter_runs === 4).length,
        sixes: playerDeliveries.filter(({ delivery }) => delivery.batter_runs === 6).length,
        strikeRate: balls > 0 ? runs / balls * 100 : 0,
        dismissal: dismissal
          ? dismissalDescription(
              dismissal.delivery.dismissal_type,
              dismissal.bowlerName,
              dismissal.delivery.fielder_season_roster_id
                ? getPlayerName(state.lineups, dismissal.delivery.fielder_season_roster_id)
                : null,
            )
          : hasAppeared
            ? 'not out'
            : 'did not bat',
        order: battingOrder.get(player.season_roster_id) ?? 1000 + lineupIndex,
      };
    })
    .sort((first, second) => first.order - second.order)
    .map((player) => ({
      playerId: player.playerId,
      name: player.name,
      isCaptain: player.isCaptain,
      isCurrent: player.isCurrent,
      runs: player.runs,
      balls: player.balls,
      fours: player.fours,
      sixes: player.sixes,
      strikeRate: player.strikeRate,
      dismissal: player.dismissal,
    }));
}

export function getCurrentBatters(
  state: MatchScoringState,
  innings: ScoringInnings,
  battingScorecard: BatterScore[],
) {
  const currentIds = new Set(
    innings.batting_turns
      .filter((turn) => turn.status === 'active')
      .map((turn) => turn.batter_season_roster_id),
  );
  const lastDelivery = flattenDeliveries(innings).at(-1)?.delivery;

  if (lastDelivery?.non_striker_season_roster_id) {
    currentIds.add(lastDelivery.non_striker_season_roster_id);
  }
  if (currentIds.size === 0 && lastDelivery) {
    currentIds.add(lastDelivery.striker_season_roster_id);
  }

  return battingScorecard
    .filter((player) => currentIds.has(player.playerId) && player.dismissal === 'not out')
    .sort((first, second) => Number(second.isCurrent) - Number(first.isCurrent))
    .slice(0, 2)
    .map((player) => ({
      ...player,
      name: getPlayerName(state.lineups, player.playerId),
    }));
}

export function getBowlingScorecard(
  state: MatchScoringState,
  innings: ScoringInnings,
): BowlerScore[] {
  const deliveries = flattenDeliveries(innings);
  const bowlerIds = [...new Set(deliveries.map(({ delivery }) => delivery.bowler_season_roster_id))];

  return bowlerIds.map((bowlerId) => {
    const bowlerDeliveries = deliveries.filter(
      ({ delivery }) => delivery.bowler_season_roster_id === bowlerId,
    );
    const legalBalls = bowlerDeliveries.filter(
      ({ delivery }) => delivery.delivery_type === 'legal',
    ).length;
    const runs = bowlerDeliveries.reduce(
      (total, { delivery }) => total + delivery.batter_runs + delivery.extra_runs,
      0,
    );
    const maidens = innings.overs.filter((over) => {
      if (over.bowler_season_roster_id !== bowlerId) return false;
      const legalDeliveries = over.deliveries.filter(
        (delivery) => delivery.delivery_type === 'legal',
      ).length;
      const overRuns = over.deliveries.reduce(
        (total, delivery) => total + delivery.batter_runs + delivery.extra_runs,
        0,
      );
      return legalDeliveries === innings.balls_per_over && overRuns === 0;
    }).length;

    return {
      playerId: bowlerId,
      name: getPlayerName(state.lineups, bowlerId),
      legalBalls,
      maidens,
      runs,
      wickets: bowlerDeliveries.filter(
        ({ delivery }) => delivery.is_wicket && delivery.dismissal_type !== 'run_out',
      ).length,
      economy: legalBalls > 0 ? runs / (legalBalls / innings.balls_per_over) : 0,
    };
  });
}

export function getExtras(innings: ScoringInnings) {
  const deliveries = flattenDeliveries(innings).map(({ delivery }) => delivery);
  const wides = deliveries
    .filter((delivery) => delivery.delivery_type === 'wide')
    .reduce((total, delivery) => total + delivery.extra_runs, 0);
  const noBalls = deliveries
    .filter((delivery) => delivery.delivery_type === 'no_ball')
    .reduce((total, delivery) => total + delivery.extra_runs, 0);
  const deadBalls = deliveries
    .filter((delivery) => delivery.delivery_type === 'dead_ball')
    .reduce((total, delivery) => total + delivery.extra_runs, 0);

  return {
    wides,
    noBalls,
    deadBalls,
    total: deliveries.reduce((total, delivery) => total + delivery.extra_runs, 0),
  };
}

export function getFallOfWickets(
  state: MatchScoringState,
  innings: ScoringInnings,
): FallOfWicket[] {
  let score = 0;
  let wicketNumber = 0;

  return flattenDeliveries(innings).flatMap(({ delivery, legalBallsAfter }) => {
    score += delivery.batter_runs + delivery.extra_runs;
    if (!delivery.is_wicket || !delivery.dismissed_season_roster_id) return [];

    wicketNumber += 1;
    return [{
      wicketNumber,
      score,
      playerName: getPlayerName(state.lineups, delivery.dismissed_season_roster_id),
      over: formatOvers(legalBallsAfter, innings.balls_per_over),
    }];
  });
}

function commentaryDescription(
  state: MatchScoringState,
  context: DeliveryContext,
) {
  const { delivery, bowlerName } = context;
  const batterName = getPlayerName(state.lineups, delivery.striker_season_roster_id);
  const prefix = `${bowlerName} to ${batterName}, `;

  if (delivery.is_wicket) {
    const fielderName = delivery.fielder_season_roster_id
      ? getPlayerName(state.lineups, delivery.fielder_season_roster_id)
      : null;
    const dismissal = delivery.dismissal_type === 'caught'
      ? `caught by ${fielderName ?? 'fielder'}`
      : delivery.dismissal_type === 'stumped'
        ? `stumped by ${fielderName ?? 'wicketkeeper'}`
        : delivery.dismissal_type === 'run_out'
          ? `run out${fielderName ? ` by ${fielderName}` : ''}`
          : delivery.dismissal_type === 'hit_wicket'
            ? 'hit wicket'
            : delivery.dismissal_type === 'hit_out_of_field'
              ? 'hit out of the field'
              : 'bowled';
    return `${prefix}${dismissal}.`;
  }
  if (delivery.delivery_type === 'wide') {
    return `${prefix}${delivery.extra_runs} wide${delivery.extra_runs === 1 ? '' : 's'}.`;
  }
  if (delivery.delivery_type === 'no_ball') {
    return `${prefix}no-ball, ${delivery.batter_runs} off the bat.`;
  }
  if (delivery.delivery_type === 'dead_ball') {
    return `${prefix}dead ball${delivery.extra_runs ? `, ${delivery.extra_runs} extra` : ''}.`;
  }
  if (delivery.batter_runs === 0) return `${prefix}no run.`;
  if (delivery.batter_runs === 4) return `${prefix}FOUR!`;
  if (delivery.batter_runs === 6) return `${prefix}SIX!`;
  return `${prefix}${delivery.batter_runs} run${delivery.batter_runs === 1 ? '' : 's'}.`;
}

export function getCommentary(
  state: MatchScoringState,
  innings: ScoringInnings,
): CommentaryItem[] {
  return flattenDeliveries(innings)
    .map((context) => {
      const { delivery } = context;
      const totalRuns = delivery.batter_runs + delivery.extra_runs;
      const badge = delivery.is_wicket
        ? 'W'
        : delivery.delivery_type === 'wide'
          ? `${delivery.extra_runs}wd`
          : delivery.delivery_type === 'no_ball'
            ? 'NB'
            : delivery.delivery_type === 'dead_ball'
              ? 'DB'
              : String(totalRuns);

      return {
        id: delivery.id,
        batterId: delivery.striker_season_roster_id,
        overNumber: context.overNumber,
        ballLabel: context.ballLabel,
        badge,
        runs: totalRuns,
        tone: delivery.is_wicket
          ? 'wicket' as const
          : delivery.batter_runs === 4 || delivery.batter_runs === 6
            ? 'boundary' as const
            : 'default' as const,
        description: commentaryDescription(state, context),
      };
    })
    .reverse();
}
