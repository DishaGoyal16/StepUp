import { Suspense, useEffect, useRef, useState } from 'react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { Activity, Bell, Footprints, Gift, LayoutDashboard, LogOut, Menu, Swords, Target, Trophy, UserRound, Users, X } from 'lucide-react'
import { Logo } from '../components/Logo'
import { Avatar, DemoBadge, Skeleton, cx } from '../components/ui'
import { longDate, greeting } from '../lib/format'
import { useApp } from '../hooks/useApp'
import { communityService } from '../services/communityService'
import { useAsync } from '../hooks/useAsync'

const NAV = [
  { to: '/', label: 'Overview', icon: LayoutDashboard, end: true },
  { to: '/activity', label: 'My Activity', icon: Activity },
  { to: '/challenges', label: 'Challenges', icon: Target },
  { to: '/battles', label: 'Step Battles', icon: Swords },
  { to: '/leaderboard', label: 'Leaderboard', icon: Trophy },
  { to: '/buddy', label: 'Sport Buddy', icon: Users },
  { to: '/rewards', label: 'Rewards', icon: Gift },
  { to: '/profile', label: 'Profile & Settings', icon: UserRound },
]

function PageFallback() {
  return (
    <div className="space-y-6" aria-busy="true" aria-label="Loading page">
      <Skeleton className="h-10 w-64" />
      <Skeleton className="h-72" />
    </div>
  )
}

function useClickOutside<T extends HTMLElement>(onOutside: () => void, active: boolean) {
  const ref = useRef<T>(null)
  useEffect(() => {
    if (!active) return
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onOutside()
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [active, onOutside])
  return ref
}

function SidebarContent({ onNavigate }: { onNavigate?: () => void }) {
  const { logout, toast } = useApp()
  const navigate = useNavigate()
  return (
    <div className="flex h-full flex-col">
      <div className="px-6 pb-6 pt-7">
        <Logo />
      </div>
      <nav className="flex-1 space-y-1 px-3" aria-label="Main">
        {NAV.map(({ to, label, icon: Icon, end }) => (
          <NavLink
            key={to}
            to={to}
            end={end}
            onClick={onNavigate}
            className={({ isActive }) =>
              cx(
                'flex items-center gap-3 rounded-2xl px-4 py-3 text-sm font-semibold transition',
                isActive ? 'bg-soft text-dark' : 'text-muted hover:bg-[#F3F6F0] hover:text-ink',
              )
            }
          >
            {({ isActive }) => (
              <>
                <Icon size={19} className={isActive ? 'text-primary' : ''} />
                {label}
              </>
            )}
          </NavLink>
        ))}
      </nav>
      <div className="space-y-3 p-4">
        <div className="rounded-2xl border border-[#F0D9A0] bg-[#FFF8E6] p-3.5">
          <DemoBadge label="DEMO MODE" />
          <p className="mt-2 text-xs leading-relaxed text-[#7a5a10]">
            No activity source is connected. Every number you see is sample data.
          </p>
        </div>
        <button
          onClick={() => {
            logout()
            toast('Signed out')
            navigate('/login')
          }}
          className="flex w-full items-center gap-3 rounded-2xl px-4 py-3 text-sm font-semibold text-muted hover:bg-[#F3F6F0] hover:text-ink"
        >
          <LogOut size={19} /> Log out
        </button>
      </div>
    </div>
  )
}

function NotificationBell() {
  const { state, markNoticesRead } = useApp()
  const [open, setOpen] = useState(false)
  const ref = useClickOutside<HTMLDivElement>(() => setOpen(false), open)
  const notices = useAsync(() => communityService.getNotices(), [])
  const unread = !state?.noticesRead && (notices.data?.length ?? 0) > 0
  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((o) => !o)}
        aria-label="Notifications"
        aria-expanded={open}
        className="relative rounded-full border border-line bg-white p-2.5 text-ink transition hover:bg-soft"
      >
        <Bell size={19} />
        {unread && <span className="absolute right-2 top-2 h-2.5 w-2.5 rounded-full border-2 border-white bg-primary" />}
      </button>
      {open && (
        <div className="fade-up absolute right-0 z-40 mt-2 w-[min(22rem,calc(100vw-2rem))] rounded-3xl border border-line bg-white p-3 shadow-2xl">
          <div className="flex items-center justify-between px-3 py-2">
            <p className="font-bold">Notifications</p>
            <button onClick={markNoticesRead} className="text-xs font-semibold text-primary hover:text-dark">
              Mark all read
            </button>
          </div>
          <ul className="max-h-80 overflow-y-auto">
            {notices.data?.map((n) => (
              <li key={n.id} className="rounded-2xl px-3 py-2.5 hover:bg-[#F7F9F5]">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-sm font-semibold">{n.title}</p>
                  <span className="text-xs text-muted">{n.time}</span>
                </div>
                <p className="text-sm text-muted">{n.body}</p>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}

function AvatarMenu() {
  const { user, logout, toast } = useApp()
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const ref = useClickOutside<HTMLDivElement>(() => setOpen(false), open)
  if (!user) return null
  return (
    <div className="relative" ref={ref}>
      <button onClick={() => setOpen((o) => !o)} aria-label="Account menu" aria-expanded={open} className="rounded-full">
        <Avatar name={user.name} size={42} />
      </button>
      {open && (
        <div className="fade-up absolute right-0 z-40 mt-2 w-60 rounded-3xl border border-line bg-white p-2 shadow-2xl">
          <div className="px-3 py-2.5">
            <p className="truncate font-bold">{user.name}</p>
            <p className="truncate text-xs text-muted">{user.email}</p>
          </div>
          <button
            onClick={() => {
              setOpen(false)
              navigate('/profile')
            }}
            className="flex w-full items-center gap-2 rounded-2xl px-3 py-2.5 text-sm font-semibold hover:bg-soft"
          >
            <UserRound size={17} /> Profile & settings
          </button>
          <button
            onClick={() => {
              logout()
              toast('Signed out')
              navigate('/login')
            }}
            className="flex w-full items-center gap-2 rounded-2xl px-3 py-2.5 text-sm font-semibold text-red-600 hover:bg-red-50"
          >
            <LogOut size={17} /> Log out
          </button>
        </div>
      )}
    </div>
  )
}

export function AppLayout() {
  const [drawer, setDrawer] = useState(false)
  const { toasts } = useApp()
  const { pathname } = useLocation()

  useEffect(() => {
    setDrawer(false)
    window.scrollTo(0, 0)
  }, [pathname])

  return (
    <div className="min-h-screen">
      {/* Desktop sidebar */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-64 border-r border-line bg-white lg:block">
        <SidebarContent />
      </aside>

      {/* Mobile drawer */}
      {drawer && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <div className="absolute inset-0 bg-ink/40 backdrop-blur-sm" onClick={() => setDrawer(false)} />
          <aside className="fade-up absolute inset-y-0 left-0 w-72 bg-white shadow-2xl">
            <button onClick={() => setDrawer(false)} aria-label="Close menu" className="absolute right-3 top-4 rounded-full p-2 text-muted hover:bg-soft">
              <X size={20} />
            </button>
            <SidebarContent onNavigate={() => setDrawer(false)} />
          </aside>
        </div>
      )}

      <div className="lg:pl-64">
        <header className="sticky top-0 z-20 border-b border-line/70 bg-bg/85 backdrop-blur-md">
          <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-4 py-3.5 sm:px-6 lg:px-8">
            <div className="flex items-center gap-3">
              <button onClick={() => setDrawer(true)} aria-label="Open menu" className="rounded-full border border-line bg-white p-2.5 lg:hidden">
                <Menu size={19} />
              </button>
              <span className="lg:hidden">
                <Logo size={32} text={false} />
              </span>
              <div>
                <p className="text-lg font-extrabold leading-tight sm:text-xl">{greeting()}</p>
                <p className="text-xs text-muted sm:text-sm">{longDate()}</p>
              </div>
            </div>
            <div className="flex items-center gap-2.5">
              <span className="hidden items-center gap-1.5 rounded-full bg-white px-3 py-1.5 text-xs font-semibold text-dark sm:inline-flex">
                <Footprints size={14} className="text-primary" /> StepUp
              </span>
              <NotificationBell />
              <AvatarMenu />
            </div>
          </div>
        </header>

        <main className="mx-auto max-w-6xl px-4 py-6 sm:px-6 sm:py-8 lg:px-8">
          <Suspense fallback={<PageFallback />}>
            <Outlet />
          </Suspense>
        </main>
      </div>

      {/* Toasts */}
      <div className="pointer-events-none fixed bottom-4 left-1/2 z-[60] flex -translate-x-1/2 flex-col items-center gap-2 px-4" aria-live="polite">
        {toasts.map((t) => (
          <div key={t.id} className="fade-up rounded-full bg-dark px-5 py-2.5 text-sm font-semibold text-white shadow-xl">
            {t.message}
          </div>
        ))}
      </div>
    </div>
  )
}
