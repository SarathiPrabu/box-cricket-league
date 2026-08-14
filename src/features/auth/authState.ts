import { createContext, useContext } from 'react';

export type LeagueRoleName = 'admin' | 'scorer' | 'player' | 'team_manager';

export type LeagueRole = {
  leagueId: string;
  leagueSlug: string;
  leagueName: string;
  role: LeagueRoleName;
};

export type AuthUser = {
  id: string;
  name: string;
  email?: string;
  picture?: string;
  subject?: string;
  roles: LeagueRole[];
  activeRole: LeagueRoleName | null;
};

export type AuthContextValue = {
  user: AuthUser | null;
  isSignedIn: boolean;
  isLoading: boolean;
  authError: string | null;
  signOut: () => Promise<void>;
  setActiveRole: (role: LeagueRoleName | null) => void;
  handleGoogleCredential: (credential: string) => Promise<void>;
};

export const AUTH_STORAGE_KEY = 'box-cricket-league.auth.user';

export const AuthContext = createContext<AuthContextValue | undefined>(
  undefined,
);

export function useAuth() {
  const context = useContext(AuthContext);

  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }

  return context;
}

export function getStoredUser() {
  if (typeof window === 'undefined') {
    return null;
  }

  const storedValue = window.localStorage.getItem(AUTH_STORAGE_KEY);

  if (!storedValue) {
    return null;
  }

  try {
    const parsedValue = JSON.parse(storedValue) as Partial<AuthUser>;

    if (
      typeof parsedValue.id !== 'string' ||
      typeof parsedValue.name !== 'string' ||
      !Array.isArray(parsedValue.roles)
    ) {
      window.localStorage.removeItem(AUTH_STORAGE_KEY);
      return null;
    }

    const validRoles = parsedValue.roles.filter(
      (role): role is LeagueRole =>
        typeof role === 'object' &&
        role !== null &&
        typeof role.role === 'string',
    );
    const activeRole =
      typeof parsedValue.activeRole === 'string' &&
      validRoles.some((role) => role.role === parsedValue.activeRole)
        ? parsedValue.activeRole
        : validRoles[0]?.role ?? null;

    return { ...parsedValue, roles: validRoles, activeRole } as AuthUser;
  } catch {
    window.localStorage.removeItem(AUTH_STORAGE_KEY);
    return null;
  }
}
