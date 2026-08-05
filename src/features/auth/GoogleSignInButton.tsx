import { GoogleLogin, type CredentialResponse } from '@react-oauth/google';
import { useAuth } from './authState';
import { isGoogleAuthConfigured } from './authConfig';

export function GoogleSignInButton() {
  const { handleGoogleCredential } = useAuth();

  if (!isGoogleAuthConfigured) {
    return (
      <span className="rounded-md border border-dashed border-slate-300 px-3 py-2 text-xs font-medium text-slate-500 dark:border-slate-700 dark:text-slate-400">
        Google sign-in not configured
      </span>
    );
  }

  return (
    <GoogleLogin
      onSuccess={(response: CredentialResponse) => {
        if (response.credential) {
          void handleGoogleCredential(response.credential);
        }
      }}
      onError={() => {
        console.error('Google sign-in failed');
      }}
      shape="pill"
      size="medium"
      text="signin_with"
      theme="outline"
    />
  );
}
