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
      className="team-badge"
    >
      {getInitials(teamName)}
    </div>
  );
}
