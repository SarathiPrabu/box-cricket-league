import { type ReactElement } from 'react';
import { useAuth, type LeagueRoleName } from '../features/auth/authState';
import { PlaceholderPage } from '../components/PlaceholderPage';
import { hasRoleForLeague } from './routeAuthorization';

type RoleProtectedRouteProps = {
  children: ReactElement;
  requiredRoles: readonly LeagueRoleName[];
  leagueSlug: string;
};

export function RoleProtectedRoute({
  children,
  requiredRoles,
  leagueSlug,
}: RoleProtectedRouteProps) {
  const { user, isLoading } = useAuth();

  if (isLoading) {
    return (
      <PlaceholderPage
        title="Checking access"
        description="Verifying your league permissions."
      />
    );
  }

  if (
    !user ||
    !hasRoleForLeague(user.roles, requiredRoles, leagueSlug, user.activeRole)
  ) {
    return (
      <PlaceholderPage
        title="Access restricted"
        description="You do not have permission to view this page."
      />
    );
  }

  return children;
}
