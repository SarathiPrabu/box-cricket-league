import type { ReactNode } from 'react';
import { TeamBadge } from '../../components/TeamBadge';

export type MatchCardData = {
  match_id: string;
  home_team_name: string;
  away_team_name: string;
  match_date: string | null;
  venue: string | null;
  status: 'draft' | 'scheduled' | 'live' | 'completed' | 'cancelled';
};

type MatchCardProps = {
  match: MatchCardData;
  canEdit?: boolean;
  isEditing?: boolean;
  onEditToggle?: () => void;
  children?: ReactNode;
};

function formatMatchDate(value: string | null) {
  if (!value) return 'Time to be confirmed';
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value));
}

function MatchCardContent({ match, canEdit, isEditing }: Pick<MatchCardProps, 'match' | 'canEdit' | 'isEditing'>) {
  return (
    <>
      <div className="match-card__header px-4 py-3 sm:px-5">
        <div className="flex items-center justify-between gap-3">
          <span className="match-card__status rounded-full px-2.5 py-1 text-xs font-bold uppercase tracking-wide">
            {match.status}
          </span>
          {canEdit ? (
            <span className="match-card__edit flex h-9 w-9 items-center justify-center rounded-full shadow-sm transition">
              <span className="sr-only">{isEditing ? 'Close fixture editor' : 'Edit fixture'}</span>
              <svg aria-hidden="true" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
                <path d="M12 20h9" strokeLinecap="round" />
                <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L8 18l-4 1 1-4Z" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </span>
          ) : null}
        </div>
      </div>
      <div className="grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center gap-3 px-4 py-6 sm:gap-6 sm:px-6">
        <div className="flex min-w-0 flex-col items-center gap-2 text-center sm:flex-row sm:text-left">
          <TeamBadge teamName={match.home_team_name} />
          <span className="break-words text-base font-extrabold tracking-tight text-slate-950 dark:text-white">{match.home_team_name}</span>
        </div>
        <span className="match-card__versus rounded-full px-2.5 py-1.5 text-xs font-black tracking-wider shadow-sm">VS</span>
        <div className="flex min-w-0 flex-col items-center gap-2 text-center sm:flex-row-reverse sm:text-right">
          <TeamBadge teamName={match.away_team_name} />
          <span className="break-words text-base font-extrabold tracking-tight text-slate-950 dark:text-white">{match.away_team_name}</span>
        </div>
      </div>
      <div className="match-card__metadata mx-4 mb-4 grid gap-2 rounded-xl p-2 text-sm font-semibold text-slate-700 dark:text-slate-200 sm:mx-6 sm:grid-cols-2">
        <span className="match-card__metadata-item flex min-h-10 items-center gap-2 rounded-lg px-3 shadow-sm">
          <svg aria-hidden="true" className="h-4 w-4 shrink-0 text-brand-600 dark:text-brand-400" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><rect height="18" rx="2" width="18" x="3" y="4" /><path d="M16 2v4M8 2v4M3 10h18" strokeLinecap="round" /></svg>
          {formatMatchDate(match.match_date)}
        </span>
        <span className="match-card__metadata-item flex min-h-10 items-center gap-2 rounded-lg px-3 shadow-sm">
          <svg aria-hidden="true" className="h-4 w-4 shrink-0 text-brand-600 dark:text-brand-400" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24"><path d="M12 21s7-5.2 7-12a7 7 0 0 0-14 0c0 6.8 7 12 7 12Z" /><circle cx="12" cy="9" r="2" /></svg>
          {match.venue || 'Community Park'}
        </span>
      </div>
    </>
  );
}

export function MatchCard({ match, canEdit = false, isEditing = false, onEditToggle, children }: MatchCardProps) {
  const content = <MatchCardContent canEdit={canEdit} isEditing={isEditing} match={match} />;

  return (
    <li className="match-card">
      {canEdit && onEditToggle ? (
        <button type="button" aria-expanded={isEditing} onClick={onEditToggle} className="block w-full text-left outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-brand-500">
          {content}
        </button>
      ) : content}
      {children}
    </li>
  );
}
