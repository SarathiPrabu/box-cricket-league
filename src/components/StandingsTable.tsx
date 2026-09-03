import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { TeamBadge } from './TeamBadge';

type StandingsSeason = { season_name: string };

type StandingsRowData = {
  season_team_id: string;
  team_slug: string;
  team_name: string;
  matches_played: number;
  wins: number;
  losses: number;
  draws: number;
  points: number;
  runs_for: number;
  balls_faced: number;
  runs_against: number;
  balls_bowled: number;
  net_run_rate: number;
};

function formatNrr(value: number) {
  return value.toFixed(2);
}

function teamAbbreviation(teamName: string) {
  const parts = teamName.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();

  return parts.map((part) => part[0] ?? '').join('').slice(0, 3).toUpperCase();
}

function formatInningsTotal(runs: number, balls: number) {
  const overs = Math.floor(balls / 6) + (balls % 6) / 10;
  return `${runs}/${overs.toFixed(1)}`;
}

const TEXT_PRIMARY = 'text-slate-950 dark:text-white';
const TEXT_MUTED = 'text-slate-600 dark:text-slate-300';
const TEXT_BODY = 'text-slate-700 dark:text-slate-300';
const TEXT_RANK = 'text-slate-500 dark:text-slate-400';
const BORDER_SUBTLE = 'border-slate-200 dark:border-slate-800';
const SURFACE = 'bg-white dark:bg-slate-900';
const CELL_BASE = 'px-1 py-2 text-sm';
const HEADER_CELL_BASE = 'px-1 py-2.5 text-xs font-semibold uppercase tracking-wide';
const SKELETON_CELL_BASE = 'px-3 py-2 sm:px-4';
const SKELETON_BLOCK = 'animate-pulse rounded bg-slate-200 motion-reduce:animate-none dark:bg-slate-800';
const INFO_CARD = `rounded-lg border ${BORDER_SUBTLE} ${SURFACE} p-5 shadow-sm`;

type ColumnDefinition = {
  key: string;
  header: ReactNode;
  widthClass: string;
  align: 'left' | 'center';
  visibilityClass?: string;
  headerPaddingClass: string;
  bodyClass: string;
  cell: (row: StandingsRowData, rank: number, selectedSeason: StandingsSeason, seasonSlugValue: string) => ReactNode;
  skeleton: () => ReactNode;
};

function SkeletonBlock({ className }: { className: string }) {
  return <div className={`${SKELETON_BLOCK} ${className}`} />;
}

function columnClassName(column: ColumnDefinition, baseClass: string, customClass = '') {
  return [
    baseClass,
    column.widthClass,
    column.visibilityClass,
    column.align === 'center' ? 'text-center' : 'text-left',
    customClass,
  ]
    .filter(Boolean)
    .join(' ');
}

const COLUMNS: ColumnDefinition[] = [
  {
    key: 'rank',
    header: <><span aria-hidden="true">#</span><span className="sr-only">Rank</span></>,
    widthClass: 'w-8 sm:w-auto',
    align: 'center',
    headerPaddingClass: 'px-1.5 sm:px-3',
    bodyClass: `font-medium tabular-nums ${TEXT_RANK} px-1.5 sm:px-3`,
    cell: (_row, rank) => rank,
    skeleton: () => <SkeletonBlock className="mx-auto h-4 w-4" />,
  },
  {
    key: 'team',
    header: 'Team',
    widthClass: 'w-24 sm:w-auto sm:min-w-48',
    align: 'left',
    headerPaddingClass: 'px-1.5 sm:px-4',
    bodyClass: 'px-1.5 sm:px-4',
    cell: (row, _rank, selectedSeason, seasonSlugValue) => {
      const teamUrl = `/teams/${row.team_slug}?season=${encodeURIComponent(seasonSlugValue)}`;

      return (
        <Link
          aria-label={`Open ${row.team_name} roster for ${selectedSeason.season_name}`}
          className="flex items-center gap-2.5 rounded-sm outline-none focus-visible:ring-2 focus-visible:ring-brand-500/50"
          to={teamUrl}
        >
          <span className="hidden sm:block"><TeamBadge teamName={row.team_name} /></span>
          <span className={`${TEXT_PRIMARY} font-semibold hover:text-brand-700 dark:hover:text-brand-400`}>
            <span className="sm:hidden">{teamAbbreviation(row.team_name)}</span>
            <span className="hidden sm:inline">{row.team_name}</span>
          </span>
        </Link>
      );
    },
    skeleton: () => (
      <div className="flex items-center gap-2.5">
        <SkeletonBlock className="h-10 w-10 shrink-0 rounded-md" />
        <SkeletonBlock className="h-4 w-36" />
      </div>
    ),
  },
  ...(['matches_played', 'wins', 'losses'] as const).map((key) => ({
    key,
    header: key === 'matches_played' ? 'M' : key === 'wins' ? 'W' : 'L',
    widthClass: 'w-8 sm:w-auto',
    align: 'center' as const,
    headerPaddingClass: 'px-1 sm:px-4',
    bodyClass: `${TEXT_BODY} tabular-nums px-1 sm:px-4`,
    cell: (row: StandingsRowData) => row[key],
    skeleton: () => <SkeletonBlock className="mx-auto h-4 w-10" />,
  })),
  {
    key: 'points',
    header: 'Pts',
    widthClass: 'w-9 sm:w-auto',
    align: 'center' as const,
    headerPaddingClass: 'px-1 sm:px-4',
    bodyClass: `${TEXT_PRIMARY} font-semibold tabular-nums px-1 sm:px-4`,
    cell: (row: StandingsRowData) => row.points,
    skeleton: () => <SkeletonBlock className="mx-auto h-4 w-10" />,
  },
  {
    key: 'net_run_rate',
    header: 'NRR',
    widthClass: 'w-11 sm:w-auto',
    align: 'center' as const,
    headerPaddingClass: 'px-1 sm:px-4',
    bodyClass: `${TEXT_PRIMARY} font-semibold tabular-nums px-1 sm:px-4`,
    cell: (row: StandingsRowData) => formatNrr(row.net_run_rate),
    skeleton: () => <SkeletonBlock className="mx-auto h-4 w-10" />,
  },
  {
    key: 'runs_for',
    header: 'For',
    widthClass: 'sm:w-auto',
    align: 'center' as const,
    visibilityClass: 'hidden sm:table-cell',
    headerPaddingClass: 'px-2 sm:px-4',
    bodyClass: `${TEXT_BODY} tabular-nums px-1 sm:px-4`,
    cell: (row: StandingsRowData) => formatInningsTotal(row.runs_for, row.balls_faced),
    skeleton: () => <SkeletonBlock className="mx-auto h-4 w-10" />,
  },
  {
    key: 'runs_against',
    header: 'Against',
    widthClass: 'sm:w-auto',
    align: 'center' as const,
    visibilityClass: 'hidden sm:table-cell',
    headerPaddingClass: 'px-2 sm:px-4',
    bodyClass: `${TEXT_BODY} tabular-nums px-1 sm:px-4`,
    cell: (row: StandingsRowData) => formatInningsTotal(row.runs_against, row.balls_bowled),
    skeleton: () => <SkeletonBlock className="mx-auto h-4 w-10" />,
  },
];

function InfoCard({ title, message, className = '' }: { title?: string; message: string; className?: string }) {
  return (
    <div className={`${INFO_CARD} ${className}`}>
      {title ? <h2 className={`${TEXT_PRIMARY} text-2xl font-semibold`}>{title}</h2> : null}
      <p className={`${title ? 'mt-2 ' : ''}text-sm ${TEXT_MUTED}`}>{message}</p>
    </div>
  );
}

function StandingsRow({
  row,
  rank,
  selectedSeason,
  seasonSlugValue,
}: {
  row: StandingsRowData;
  rank: number;
  selectedSeason: StandingsSeason;
  seasonSlugValue: string;
}) {
  return (
    <tr className={`border-t ${BORDER_SUBTLE} transition hover:bg-emerald-50/50 motion-reduce:transition-none dark:hover:bg-emerald-950/20`}>
      {COLUMNS.map((column) => (
        <td className={columnClassName(column, CELL_BASE, column.bodyClass)} key={column.key}>
          {column.cell(row, rank, selectedSeason, seasonSlugValue)}
        </td>
      ))}
    </tr>
  );
}

export function StandingsTable({
  standings,
  selectedSeason,
  seasonSlugValue,
  loading = false,
}: {
  standings?: StandingsRowData[];
  selectedSeason?: StandingsSeason;
  seasonSlugValue?: string;
  loading?: boolean;
}) {
  return (
    <div className={`mt-6 overflow-x-auto rounded-lg border ${BORDER_SUBTLE} ${SURFACE} shadow-sm`}>
      <table className="w-full min-w-[336px] table-fixed border-collapse text-left sm:min-w-[840px] sm:table-auto">
        <thead className="bg-slate-50 dark:bg-slate-950/60">
          <tr>{COLUMNS.map((column) => <th className={columnClassName(column, `${HEADER_CELL_BASE} ${TEXT_MUTED}`, column.headerPaddingClass)} key={column.key} scope="col">{column.header}</th>)}</tr>
        </thead>
        <tbody>
          {loading
            ? Array.from({ length: 6 }).map((_, index) => <tr className={`border-t ${BORDER_SUBTLE}`} key={index}>{COLUMNS.map((column) => <td className={columnClassName(column, SKELETON_CELL_BASE)} key={column.key}>{column.skeleton()}</td>)}</tr>)
            : standings && selectedSeason
              ? standings.map((row, index) => <StandingsRow key={row.season_team_id} rank={index + 1} row={row} selectedSeason={selectedSeason} seasonSlugValue={seasonSlugValue ?? ''} />)
              : null}
        </tbody>
      </table>
    </div>
  );
}

export { InfoCard };
