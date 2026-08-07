type TeamBadgeProps = {
  teamName: string;
  logoUrl?: string | null;
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

export function TeamBadge({ teamName, logoUrl }: TeamBadgeProps) {
  return (
    <div
      aria-hidden="true"
      className="team-badge"
    >
      {logoUrl ? <img alt="" src={logoUrl} /> : getInitials(teamName)}
    </div>
  );
}
