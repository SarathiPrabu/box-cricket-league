import { createBrowserRouter } from 'react-router-dom';
import { AppLayout } from './AppLayout';
import { LeaderboardsPage } from '../features/leaderboards/LeaderboardsPage';
import { MatchesPage } from '../features/matches/MatchesPage';
import { HomePage } from '../features/home/HomePage';
import { PlayerDetailPage } from '../features/players/PlayerDetailPage';
import { PlayersPage } from '../features/players/PlayersPage';
import { TeamDetailPage } from '../features/teams/TeamDetailPage';
import { TeamsPage } from '../features/teams/TeamsPage';

export const router = createBrowserRouter([
  {
    path: '/',
    element: <AppLayout />,
    children: [
      { index: true, element: <HomePage /> },
      { path: 'players', element: <PlayersPage /> },
      { path: 'players/:slug', element: <PlayerDetailPage /> },
      { path: 'teams', element: <TeamsPage /> },
      { path: 'teams/:slug', element: <TeamDetailPage /> },
      { path: 'matches', element: <MatchesPage /> },
      { path: 'leaderboards', element: <LeaderboardsPage /> },
    ],
  },
]);
