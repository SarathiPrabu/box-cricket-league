export type MatchStatus = 'draft' | 'scheduled' | 'live' | 'completed' | 'cancelled';

export type MatchResultType = 'win' | 'tie' | 'no_result';

export type DeliveryType = 'legal' | 'wide' | 'no_ball' | 'dead_ball';

export type DismissalType = 'bowled' | 'caught' | 'stumped' | 'hit_wicket' | 'hit_out_of_field';

export type RecordedDismissalType = DismissalType | 'run_out';

export type ScoringMatch = {
  id: string;
  season_id: string;
  status: MatchStatus;
  result_type: MatchResultType | null;
  winner_season_team_id: string | null;
  home_season_team_id: string;
  away_season_team_id: string;
  home_team_name: string;
  away_team_name: string;
  match_date: string | null;
  venue: string | null;
  historical_batting_exception: boolean;
  balls_per_over: number;
  max_overs_per_player: number;
};

export type ScoringLineup = {
  id: string;
  season_team_id: string;
  season_roster_id: string;
  player_id: string;
  player_name: string;
  is_captain: boolean;
};

export type ScoringDelivery = {
  id: string;
  batting_turn_id: string | null;
  delivery_sequence: number;
  legal_ball_number: number | null;
  striker_season_roster_id: string;
  non_striker_season_roster_id: string | null;
  bowler_season_roster_id: string;
  delivery_type: DeliveryType;
  batter_runs: number;
  extra_runs: number;
  is_wicket: boolean;
  dismissed_season_roster_id: string | null;
  dismissal_type: RecordedDismissalType | null;
  fielder_season_roster_id: string | null;
};

export type BattingTurnPhase = 'initial' | 'flexible';

export type BattingTurnEndReason = 'six_balls' | 'dismissed' | 'switched' | 'innings_end';

export type ScoringBattingTurn = {
  id: string;
  turn_number: number;
  batter_season_roster_id: string;
  batter_name: string;
  phase: BattingTurnPhase;
  status: 'active' | 'ended';
  end_reason: BattingTurnEndReason | null;
  legal_balls_faced: number;
};

export type ScoringOver = {
  id: string;
  over_number: number;
  confirmed_at: string | null;
  batting_slot_season_roster_id: string | null;
  bowler_season_roster_id: string;
  wicketkeeper_season_roster_id: string;
  batting_slot_name: string | null;
  bowler_name: string;
  wicketkeeper_name: string;
  deliveries: ScoringDelivery[];
};

export type ScoringInnings = {
  id: string;
  innings_number: number;
  batting_season_team_id: string;
  bowling_season_team_id: string;
  overs_limit: number;
  balls_per_over: number;
  legal_balls_limit: number;
  max_overs_per_player: number;
  target_score: number | null;
  status: 'live' | 'completed';
  batting_turns: ScoringBattingTurn[];
  overs: ScoringOver[];
};

export type MatchScoringState = {
  match: ScoringMatch;
  lineups: ScoringLineup[];
  innings: ScoringInnings[];
};
