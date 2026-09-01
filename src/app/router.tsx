import { createBrowserRouter } from 'react-router-dom';
import { AppLayout } from './AppLayout';
import { RoleAssignmentPage } from '../features/admin/RoleAssignmentPage';
import { TeamManagerAssignmentPage } from '../features/admin/TeamManagerAssignmentPage';
import { LeaderboardsPage } from '../features/leaderboards/LeaderboardsPage';
import { MatchesPage } from '../features/matches/MatchesPage';
import { LiveMatchPage } from '../features/matches/LiveMatchPage';
import { BulkEntryPage } from '../features/matches/BulkEntryPage';
import { PublicLiveScorePage } from '../features/matches/PublicLiveScorePage';
import { TeamSelectionPage } from '../features/matches/TeamSelectionPage';
import { HomePage } from '../features/home/HomePage';
import { PlayerDetailPage } from '../features/players/PlayerDetailPage';
import { PlayersPage } from '../features/players/PlayersPage';
import { StandingsPage } from '../features/standings/StandingsPage';
import { TeamDetailPage } from '../features/teams/TeamDetailPage';
import { TeamsPage } from '../features/teams/TeamsPage';
import { protectRoute } from './routeAccess';

export const router = createBrowserRouter([
  {
    path: '/',
    element: <AppLayout />,
    children: [
      { index: true, element: <HomePage /> },
      {
        path: 'admin/roles',
        element: protectRoute('adminRoles', <RoleAssignmentPage />),
      },
      {
        path: 'admin/team-managers',
        element: protectRoute('teamManagers', <TeamManagerAssignmentPage />),
      },
      { path: 'players', element: <PlayersPage /> },
      { path: 'players/:slug', element: <PlayerDetailPage /> },
      { path: 'teams', element: <TeamsPage /> },
      { path: 'teams/:slug', element: <TeamDetailPage /> },
      { path: 'matches', element: <MatchesPage /> },
      { path: 'matches/:matchId', element: <PublicLiveScorePage /> },
      { path: 'matches/:matchId/live', element: <LiveMatchPage /> },
      { path: 'matches/:matchId/live/bulk', element: <BulkEntryPage /> },
      { path: 'matches/:matchId/lineup', element: protectRoute('teamSelection', <TeamSelectionPage />) },
      { path: 'standings', element: <StandingsPage /> },
      { path: 'leaderboards', element: <LeaderboardsPage /> },
    ],
  },
]);
