import { type ReactElement } from 'react';
import { RoleProtectedRoute } from './RoleProtectedRoute';
import { hasRoleForLeague } from './routeAuthorization';
import type { AuthUser, LeagueRoleName } from '../features/auth/authState';
import { roleAccessEnabled } from './accessMode';

const activeLeagueSlug = 'box-cricket-league';

export const routeAccess = {
  adminRoles: {
    leagueSlug: activeLeagueSlug,
    requiredRoles: ['admin'],
  },
  teamManagers: {
    leagueSlug: activeLeagueSlug,
    requiredRoles: ['admin'],
  },
  teamSelection: {
    leagueSlug: activeLeagueSlug,
    requiredRoles: ['admin', 'team_manager'],
  },
} satisfies Record<string, { leagueSlug: string; requiredRoles: readonly LeagueRoleName[] }>;

export type ProtectedRouteName = keyof typeof routeAccess;

export function protectRoute(
  routeName: ProtectedRouteName,
  element: ReactElement,
) {
  if (!roleAccessEnabled) {
    return element;
  }

  const access = routeAccess[routeName];

  return (
    <RoleProtectedRoute
      requiredRoles={access.requiredRoles}
      leagueSlug={access.leagueSlug}
    >
      {element}
    </RoleProtectedRoute>
  );
}

export function canAccessRoute(
  user: AuthUser | null,
  routeName: ProtectedRouteName,
) {
  if (!roleAccessEnabled) {
    return true;
  }

  const access = routeAccess[routeName];

  return Boolean(
    user &&
      hasRoleForLeague(
        user.roles,
        access.requiredRoles,
        access.leagueSlug,
        user.activeRole,
      ),
  );
}
