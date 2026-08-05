type TeamBadgeProps = {
  teamName: string;
};

function getInitials(teamName: string) {
  return teamName
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0] ?? '')
    .join('')
    .toUpperCase() || 'T';
}

export function TeamBadge({ teamName }: TeamBadgeProps) {
  return (
    <div
      aria-hidden="true"
      className="flex h-10 w-10 shrink-0 items-center justify-center rounded-md border border-emerald-200 bg-emerald-50 text-sm font-bold text-emerald-800 dark:border-emerald-900/70 dark:bg-emerald-950 dark:text-emerald-200"
    >
      {getInitials(teamName)}
    </div>
  );
}
