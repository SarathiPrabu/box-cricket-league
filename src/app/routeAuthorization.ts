import type { AuthUser, LeagueRoleName } from '../features/auth/authState';

export function hasRoleForLeague(
  roles: AuthUser['roles'],
  requiredRoles: readonly LeagueRoleName[],
  leagueSlug: string,
) {
  return roles.some(
    (role) =>
      role.leagueSlug === leagueSlug && requiredRoles.includes(role.role),
  );
}
