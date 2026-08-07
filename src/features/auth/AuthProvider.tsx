import { type ReactNode, useEffect, useState } from 'react';
import { type User } from '@supabase/supabase-js';
import {
  AUTH_STORAGE_KEY,
  AuthContext,
  getStoredUser,
  type AuthUser,
  type LeagueRole,
  type LeagueRoleName,
} from './authState';
import { isSupabaseConfigured, supabase } from '../../lib/supabase';

type LeagueRoleRow = {
  league_id: string;
  league_slug: string;
  league_name: string;
  role: LeagueRoleName;
};

function getUserName(user: User) {
  const metadata = user.user_metadata;
  const metadataName =
    typeof metadata.name === 'string' ? metadata.name.trim() : '';
  const fullName =
    typeof metadata.full_name === 'string' ? metadata.full_name.trim() : '';

  if (metadataName) {
    return metadataName;
  }

  if (fullName) {
    return fullName;
  }

  if (user.email) {
    return user.email.split('@')[0] ?? user.email;
  }

  return 'Player';
}

function getUserPicture(user: User) {
  const metadata = user.user_metadata;

  if (typeof metadata.picture === 'string') {
    return metadata.picture;
  }

  if (typeof metadata.avatar_url === 'string') {
    return metadata.avatar_url;
  }

  return undefined;
}

async function loadLeagueRoles() {
  if (!supabase || !isSupabaseConfigured) {
    return [];
  }

  const { data, error } = await supabase.rpc('get_my_league_roles');

  if (error) {
    throw error;
  }

  return ((data ?? []) as LeagueRoleRow[]).map((roleRow): LeagueRole => {
    return {
      leagueId: roleRow.league_id,
      leagueSlug: roleRow.league_slug,
      leagueName: roleRow.league_name,
      role: roleRow.role,
    };
  });
}

async function buildAuthUser(user: User) {
  const roles = await loadLeagueRoles();

  return {
    id: user.id,
    name: getUserName(user),
    email: user.email,
    picture: getUserPicture(user),
    subject: user.id,
    roles,
    activeRole: roles[0]?.role ?? null,
  } satisfies AuthUser;
}

function withPreservedActiveRole(nextUser: AuthUser, previousUser: AuthUser | null) {
  const activeRole = previousUser?.activeRole;

  return {
    ...nextUser,
    activeRole:
      activeRole && nextUser.roles.some((role) => role.role === activeRole)
        ? activeRole
        : nextUser.roles[0]?.role ?? null,
  };
}

function getAuthErrorMessage(error: unknown) {
  if (error instanceof Error) {
    if (
      error.message === 'Failed to fetch' ||
      error.message.includes('fetch failed')
    ) {
      return 'Could not call Supabase Auth from this app URL. Check Supabase Auth URL configuration, Google provider settings, and browser console CORS/network details.';
    }

    return error.message;
  }

  return 'Google sign-in failed.';
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AuthUser | null>(() => getStoredUser());
  const [isLoading, setIsLoading] = useState(true);
  const [authError, setAuthError] = useState<string | null>(null);

  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }

    if (user) {
      window.localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(user));
      return;
    }

    window.localStorage.removeItem(AUTH_STORAGE_KEY);
  }, [user]);

  useEffect(() => {
    let isMounted = true;

    async function loadSession() {
      if (!supabase || !isSupabaseConfigured) {
        setIsLoading(false);
        return;
      }

      const { data, error } = await supabase.auth.getSession();

      if (!isMounted) {
        return;
      }

      if (error) {
        setAuthError(error.message);
        setUser(null);
        setIsLoading(false);
        return;
      }

      if (!data.session?.user) {
        setUser(null);
        setIsLoading(false);
        return;
      }

      try {
        const nextUser = await buildAuthUser(data.session.user);
        setUser((previousUser) => withPreservedActiveRole(nextUser, previousUser));
        setAuthError(null);
      } catch (roleError) {
        setAuthError(
          roleError instanceof Error
            ? roleError.message
            : 'Unable to load user roles.',
        );
      } finally {
        setIsLoading(false);
      }
    }

    void loadSession();

    const { data: listener } =
      supabase?.auth.onAuthStateChange((_event, session) => {
        if (!session?.user) {
          setUser(null);
          return;
        }

        void buildAuthUser(session.user)
          .then((nextUser) => {
            setUser((previousUser) =>
              withPreservedActiveRole(nextUser, previousUser),
            );
            setAuthError(null);
          })
          .catch((roleError: unknown) => {
            setAuthError(
              roleError instanceof Error
                ? roleError.message
                : 'Unable to load user roles.',
            );
          });
      }) ?? { data: { subscription: null } };

    return () => {
      isMounted = false;
      listener.subscription?.unsubscribe();
    };
  }, []);

  const handleGoogleCredential = async (credential: string) => {
    if (!credential) {
      return;
    }

    if (!supabase || !isSupabaseConfigured) {
      setAuthError('Supabase is not configured.');
      return;
    }

    setIsLoading(true);
    setAuthError(null);

    try {
      const { data, error } = await supabase.auth.signInWithIdToken({
        provider: 'google',
        token: credential,
      });

      if (error) {
        throw error;
      }

      if (data.user) {
        const nextUser = await buildAuthUser(data.user);
        setUser((previousUser) => withPreservedActiveRole(nextUser, previousUser));
      }
    } catch (error) {
      setAuthError(getAuthErrorMessage(error));
    } finally {
      setIsLoading(false);
    }
  };

  const signOut = async () => {
    if (supabase && isSupabaseConfigured) {
      await supabase.auth.signOut();
    }

    setUser(null);
  };

  const setActiveRole = (role: LeagueRoleName | null) => {
    setUser((previousUser) => {
      if (!previousUser) return previousUser;

      const nextRole =
        role === null || previousUser.roles.some((assignedRole) => assignedRole.role === role)
          ? role
          : previousUser.activeRole;

      return { ...previousUser, activeRole: nextRole };
    });
  };

  return (
    <AuthContext.Provider
      value={{
        user,
        isSignedIn: user !== null,
        isLoading,
        authError,
        signOut,
        setActiveRole,
        handleGoogleCredential,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}
