import { Link } from 'react-router-dom';
import { TeamBadge } from './TeamBadge';
import type { MatchCardData } from './MatchCard';

export type HomeMatchData = MatchCardData & {
  home_season_team_id: string;
  away_season_team_id: string;
  home_runs: number | null;
  home_wickets: number | null;
  home_legal_balls: number | null;
  home_balls_per_over: number | null;
  away_runs: number | null;
  away_wickets: number | null;
  away_legal_balls: number | null;
  away_balls_per_over: number | null;
  win_margin: { amount: number; type: 'run' | 'wicket' } | null;
};

type HomeMatchCardProps = {
  match: HomeMatchData;
};

function formatMatchDate(value: string | null) {
  if (!value) return 'Date TBD';

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Date TBD';

  return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(date);
}

function formatOvers(legalBalls: number | null, ballsPerOver: number | null) {
  if (legalBalls === null || ballsPerOver === null || ballsPerOver < 1) return null;
  return `${Math.floor(legalBalls / ballsPerOver)}.${legalBalls % ballsPerOver} ov`;
}

function resultLabel(match: HomeMatchData) {
  if (match.status === 'live') return 'Match in progress';
  if (match.status !== 'completed') return 'Match scheduled';
  if (match.result_type === 'win' && match.winner_team_name) {
    if (!match.win_margin) return `${match.winner_team_name} won`;
    const unit = match.win_margin.amount === 1 ? match.win_margin.type : `${match.win_margin.type}s`;
    return `${match.winner_team_name} won by ${match.win_margin.amount} ${unit}`;
  }
  if (match.result_type === 'forfeit' && match.winner_team_name) return `${match.winner_team_name} won by forfeit`;
  if (match.result_type === 'tie') return 'Match tied';
  if (match.result_type === 'no_result') return 'No result';
  return 'Match completed';
}

function statusLabel(status: HomeMatchData['status']) {
  if (status === 'live') return 'Live';
  if (status === 'completed') return 'Result';
  return 'Upcoming';
}

function TeamScore({
  name,
  runs,
  wickets,
  legalBalls,
  ballsPerOver,
  isWinner,
}: {
  name: string;
  runs: number | null;
  wickets: number | null;
  legalBalls: number | null;
  ballsPerOver: number | null;
  isWinner: boolean;
}) {
  const overs = formatOvers(legalBalls, ballsPerOver);
  const hasScore = runs !== null && wickets !== null;

  return (
    <div className={`home-result-card__team${isWinner ? ' home-result-card__team--winner' : ''}`}>
      <TeamBadge teamName={name} />
      <span className="home-result-card__team-name">{name}</span>
      <span className="home-result-card__score">
        {overs ? <small>({overs})</small> : null}
        <strong>{hasScore ? `${runs}/${wickets}` : '—'}</strong>
      </span>
    </div>
  );
}

export function HomeMatchCard({ match }: HomeMatchCardProps) {
  const homeIsWinner = match.result_type === 'win' && match.winner_team_name === match.home_team_name;
  const awayIsWinner = match.result_type === 'win' && match.winner_team_name === match.away_team_name;
  const hasDetailedScore = match.home_runs !== null || match.away_runs !== null;
  const canViewScore = match.status === 'live' || (match.status === 'completed' && hasDetailedScore);

  const card = (
    <article className="home-result-card">
      <header className="home-result-card__header">
        <span className={`home-result-card__status home-result-card__status--${match.status}`}>
          {statusLabel(match.status)}
        </span>
        <span>{formatMatchDate(match.match_date)}</span>
      </header>

      <div className="home-result-card__teams">
        <TeamScore
          ballsPerOver={match.home_balls_per_over}
          isWinner={homeIsWinner}
          legalBalls={match.home_legal_balls}
          name={match.home_team_name}
          runs={match.home_runs}
          wickets={match.home_wickets}
        />
        <TeamScore
          ballsPerOver={match.away_balls_per_over}
          isWinner={awayIsWinner}
          legalBalls={match.away_legal_balls}
          name={match.away_team_name}
          runs={match.away_runs}
          wickets={match.away_wickets}
        />
      </div>

      <footer className="home-result-card__result">{resultLabel(match)}</footer>
    </article>
  );

  return canViewScore ? (
    <Link
      aria-label={`${match.status === 'live' ? 'View live score' : 'View scorecard'} for ${match.home_team_name} versus ${match.away_team_name}`}
      className="block rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-slate-950"
      to={`/matches/${match.match_id}`}
    >
      {card}
    </Link>
  ) : card;
}
