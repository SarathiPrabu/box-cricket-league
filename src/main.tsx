import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { GoogleOAuthProvider } from '@react-oauth/google';
import { RouterProvider } from 'react-router-dom';
import { router } from './app/router';
import { isGoogleAuthConfigured } from './features/auth/authConfig';
import { AuthProvider } from './features/auth/AuthProvider';
import './index.css';

const rootElement = document.getElementById('root');

if (!rootElement) {
  throw new Error('Root element not found');
}

createRoot(rootElement).render(
  <StrictMode>
    <AuthProvider>
      {isGoogleAuthConfigured ? (
        <GoogleOAuthProvider clientId={import.meta.env.VITE_GOOGLE_CLIENT_ID}>
          <RouterProvider router={router} />
        </GoogleOAuthProvider>
      ) : (
        <RouterProvider router={router} />
      )}
    </AuthProvider>
  </StrictMode>,
);
