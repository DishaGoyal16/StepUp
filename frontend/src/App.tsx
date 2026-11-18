import { lazy, Suspense, type ReactNode } from 'react'
import { Link, Navigate, Route, Routes, useLocation } from 'react-router-dom'
import { AppLayout } from './layouts/AppLayout'
import { useApp } from './hooks/useApp'
import { LoginPage, RegisterPage } from './pages/Auth'

// Route-level code splitting keeps the first load small (Recharts is only pulled in by chart pages)
const Overview = lazy(() => import('./pages/Overview'))
const ActivityPage = lazy(() => import('./pages/ActivityPage'))
const ChallengesPage = lazy(() => import('./pages/ChallengesPage'))
const BattlesPage = lazy(() => import('./pages/BattlesPage'))
const LeaderboardPage = lazy(() => import('./pages/LeaderboardPage'))
const BuddyPage = lazy(() => import('./pages/BuddyPage'))
const RewardsPage = lazy(() => import('./pages/RewardsPage'))
const ProfilePage = lazy(() => import('./pages/ProfilePage'))


function RequireAuth({ children }: { children: ReactNode }) {
  const { user } = useApp()
  const location = useLocation()
  if (!user) return <Navigate to="/login" replace state={{ from: location.pathname }} />
  return <>{children}</>
}

function NotFound() {
  return (
    <div className="py-24 text-center">
      <p className="text-5xl font-extrabold text-primary">404</p>
      <p className="mt-2 text-muted">That page doesn't exist.</p>
      <Link to="/" className="mt-4 inline-block font-semibold text-primary hover:text-dark">Back to Overview</Link>
    </div>
  )
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/register" element={<RegisterPage />} />
      <Route
        element={
          <RequireAuth>
            <AppLayout />
          </RequireAuth>
        }
      >
        <Route index element={<Overview />} />
        <Route path="activity" element={<ActivityPage />} />
        <Route path="challenges" element={<ChallengesPage />} />
        <Route path="battles" element={<BattlesPage />} />
        <Route path="leaderboard" element={<LeaderboardPage />} />
        <Route path="buddy" element={<BuddyPage />} />
        <Route path="rewards" element={<RewardsPage />} />
        <Route path="profile" element={<ProfilePage />} />
        <Route path="*" element={<NotFound />} />
      </Route>
    </Routes>
  )
}
