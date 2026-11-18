import { Link } from 'react-router-dom'
import { ArrowRight, Check, Clock, Flame, Info, MapPin, Zap } from 'lucide-react'
import { WeeklyBarChart } from '../components/charts'
import { getIcon } from '../components/icons'
import { ProgressRing } from '../components/ProgressRing'
import { StatCard } from '../components/StatCard'
import { Button, Card, CardHeader, DemoBadge, EmptyState, ErrorState, Pill, ProgressBar, Skeleton } from '../components/ui'
import { useAppState } from '../hooks/useApp'
import { useAsync } from '../hooks/useAsync'
import { useStats } from '../hooks/useStats'
import { distance, fmt, shortDay } from '../lib/format'
import { pct } from '../lib/stats'
import { activityService } from '../services/activityService'
import { communityService } from '../services/communityService'

function motivation(percent: number, remaining: number): string {
  if (percent >= 100) return 'Goal smashed! Everything from here is a bonus.'
  if (percent >= 75) return `Nearly there — about ${fmt(remaining)} steps to go. A brisk 20-minute walk should do it.`
  if (percent >= 40) return `Solid progress. ${fmt(remaining)} steps left to hit today's goal.`
  return `Good start. Let's chip away at those ${fmt(remaining)} steps.`
}

export default function Overview() {
  const state = useAppState()
  const { user } = state
  const { derived, loading, error, reload } = useStats()
  const sessions = useAsync(() => activityService.getSessions(), [])
  const challenges = useAsync(() => communityService.getChallenges(), [])

  if (error) return <ErrorState message={error} onRetry={reload} />
  if (loading || !derived) return <OverviewSkeleton />

  const { today, week, streak, badges } = derived
  const goal = user.dailyGoal
  const percent = pct(today.steps, goal)
  const remaining = Math.max(0, goal - today.steps)

  const joined = (challenges.data ?? []).filter((c) => c.id in state.joined)
  const earned = badges.filter((b) => b.earned).slice(0, 4)

  return (
    <div className="space-y-6">
      {/* Demo banner */}
      <div role="note" className="flex items-start gap-3 rounded-2xl border border-[#F0D9A0] bg-[#FFF8E6] px-4 py-3 text-sm text-[#7a5a10]">
        <Info size={18} className="mt-0.5 shrink-0" />
        <p>
          <strong>Demo data.</strong> These activity numbers are sample values for preview. They are not coming from a real step counter or
          health source yet.
        </p>
      </div>

      {/* Hero */}
      <Card className="relative overflow-hidden bg-gradient-to-br from-white via-white to-soft p-6 sm:p-8">
        <div className="pointer-events-none absolute -right-24 -top-24 h-72 w-72 rounded-full bg-lime/20 blur-3xl" />
        <div className="relative grid items-center gap-8 xl:grid-cols-[minmax(0,320px)_1fr]">
          <ProgressRing value={percent} size={300} stroke={26} label={`${percent}% of daily goal`}>
            <span className="text-xs font-bold uppercase tracking-widest text-muted">Today</span>
            <span className="text-5xl font-extrabold tracking-tight text-ink sm:text-6xl">{fmt(today.steps)}</span>
            <span className="text-sm font-semibold text-muted">steps</span>
            <span className="mt-2 rounded-full bg-soft px-3 py-1 text-sm font-extrabold text-dark">{percent}%</span>
          </ProgressRing>

          <div>
            <div className="mb-1 flex flex-wrap items-center gap-2">
              <h1 className="text-2xl font-extrabold tracking-tight sm:text-3xl">Today's steps</h1>
              <DemoBadge />
            </div>
            <p className="max-w-lg text-muted">{motivation(percent, remaining)}</p>

            <dl className="mt-5 grid grid-cols-3 gap-3">
              <div className="rounded-2xl bg-white/80 p-3.5 ring-1 ring-line">
                <dt className="text-xs font-semibold text-muted">Daily goal</dt>
                <dd className="mt-0.5 text-xl font-extrabold">{fmt(goal)}</dd>
              </div>
              <div className="rounded-2xl bg-white/80 p-3.5 ring-1 ring-line">
                <dt className="text-xs font-semibold text-muted">Progress</dt>
                <dd className="mt-0.5 text-xl font-extrabold text-primary">{percent}%</dd>
              </div>
              <div className="rounded-2xl bg-white/80 p-3.5 ring-1 ring-line">
                <dt className="text-xs font-semibold text-muted">Remaining</dt>
                <dd className="mt-0.5 text-xl font-extrabold">{fmt(remaining)}</dd>
              </div>
            </dl>
          </div>
        </div>

        <div className="relative mt-6 grid grid-cols-2 gap-3 md:grid-cols-4">
          <StatCard icon={MapPin} label="Distance" value={distance(today.distanceKm, user.units)} note="estimated" />
          <StatCard icon={Flame} label="Calories" value={`${fmt(today.calories)} kcal`} note="estimated" />
          <StatCard icon={Clock} label="Active minutes" value={`${today.activeMinutes} min`} />
          <StatCard icon={Zap} label="Streak" value={`${streak} ${streak === 1 ? 'day' : 'days'}`} note="goal days in a row" />
        </div>
      </Card>

      {/* Weekly chart + daily goal tracker */}
      <div className="grid gap-6 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader title="Weekly steps" subtitle="Last 7 days · dashed line is your goal" action={<DemoBadge />} />
          <WeeklyBarChart data={week} goal={goal} />
        </Card>

        <Card>
          <CardHeader title="Daily goal progress" subtitle={`Goal: ${fmt(goal)} steps`} />
          <ul className="grid grid-cols-7 gap-1.5">
            {week.map((d, i) => {
              const met = d.steps >= goal
              const isToday = i === week.length - 1
              return (
                <li key={d.date} className="flex flex-col items-center gap-1.5">
                  <span
                    className={`flex h-9 w-9 items-center justify-center rounded-full text-xs font-bold ${
                      met ? 'bg-primary text-white' : isToday ? 'bg-lime/30 text-dark ring-2 ring-lime' : 'bg-soft text-muted'
                    }`}
                    title={`${fmt(d.steps)} steps`}
                  >
                    {met ? <Check size={16} /> : pct(d.steps, goal)}
                  </span>
                  <span className="text-[11px] font-semibold text-muted">{shortDay(d.date).slice(0, 2)}</span>
                </li>
              )
            })}
          </ul>
          <div className="mt-5">
            <div className="mb-1.5 flex justify-between text-sm">
              <span className="font-semibold">Today</span>
              <span className="text-muted">{fmt(today.steps)} / {fmt(goal)}</span>
            </div>
            <ProgressBar value={percent} label="Today's goal progress" />
          </div>
          <p className="mt-4 text-sm text-muted">
            {week.filter((d) => d.steps >= goal).length} of 7 days at goal this week.
          </p>
        </Card>
      </div>

      {/* Recent activity + challenges */}
      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader title="Recent activity" action={<Link to="/activity" className="text-sm font-semibold text-primary hover:text-dark">View all</Link>} />
          {sessions.loading ? (
            <div className="space-y-3">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-14" />)}</div>
          ) : (
            <ul className="divide-y divide-line">
              {sessions.data?.slice(0, 4).map((s) => (
                <li key={s.id} className="flex items-center gap-3 py-3">
                  <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-soft text-xs font-extrabold text-dark">{s.type}</span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-semibold">{s.title}</p>
                    <p className="text-xs text-muted">{s.when} · {s.durationMin} min</p>
                  </div>
                  <div className="text-right">
                    <p className="font-extrabold">{fmt(s.steps)}</p>
                    <p className="text-xs text-muted">steps</p>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card>
          <CardHeader title="Fitness challenges" action={<Link to="/challenges" className="text-sm font-semibold text-primary hover:text-dark">Browse</Link>} />
          {challenges.loading ? (
            <div className="space-y-3">{[0, 1].map((i) => <Skeleton key={i} className="h-20" />)}</div>
          ) : joined.length === 0 ? (
            <EmptyState
              title="No active challenges"
              body="Join a challenge to compete for points and badges."
              action={<Link to="/challenges"><Button size="sm">Find a challenge <ArrowRight size={15} /></Button></Link>}
            />
          ) : (
            <ul className="space-y-4">
              {joined.slice(0, 3).map((c) => {
                const Icon = getIcon(c.icon)
                const p = pct(state.joined[c.id], c.targetSteps)
                return (
                  <li key={c.id} className="rounded-2xl border border-line p-4">
                    <div className="flex items-center gap-3">
                      <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-soft text-primary"><Icon size={19} /></span>
                      <div className="min-w-0 flex-1">
                        <p className="truncate font-bold">{c.title}</p>
                        <p className="text-xs text-muted">{fmt(state.joined[c.id])} / {fmt(c.targetSteps)} steps</p>
                      </div>
                      <Pill>{p}%</Pill>
                    </div>
                    <ProgressBar value={p} className="mt-3" label={`${c.title} progress`} />
                  </li>
                )
              })}
            </ul>
          )}
        </Card>
      </div>

      {/* Achievements */}
      <Card>
        <CardHeader title="Recent achievements" action={<Link to="/rewards" className="text-sm font-semibold text-primary hover:text-dark">All rewards</Link>} />
        {earned.length === 0 ? (
          <EmptyState title="No badges yet" body="Hit your daily goal or join a challenge to earn your first badge." />
        ) : (
          <ul className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {earned.map((b) => {
              const Icon = getIcon(b.icon)
              return (
                <li key={b.id} className="flex flex-col items-center rounded-2xl bg-soft/70 p-4 text-center">
                  <span className="mb-2 flex h-12 w-12 items-center justify-center rounded-full bg-gradient-to-br from-lime to-primary text-white shadow-sm">
                    <Icon size={22} />
                  </span>
                  <p className="text-sm font-bold">{b.name}</p>
                  <p className="text-xs text-muted">{b.description}</p>
                </li>
              )
            })}
          </ul>
        )}
      </Card>
    </div>
  )
}

function OverviewSkeleton() {
  return (
    <div className="space-y-6" aria-busy="true" aria-label="Loading dashboard">
      <Skeleton className="h-12" />
      <Skeleton className="h-96" />
      <div className="grid gap-6 lg:grid-cols-3">
        <Skeleton className="h-72 lg:col-span-2" />
        <Skeleton className="h-72" />
      </div>
    </div>
  )
}
