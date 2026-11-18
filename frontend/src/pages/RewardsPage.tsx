import { Check, Lock, Sparkles } from 'lucide-react'
import { getIcon } from '../components/icons'
import { Button, Card, CardHeader, ErrorState, PageHeader, Pill, ProgressBar, Skeleton, cx } from '../components/ui'
import { MILESTONES, STREAK_REWARDS } from '../data/demo'
import { useApp, useAppState } from '../hooks/useApp'
import { useStats } from '../hooks/useStats'
import { fmt } from '../lib/format'

const LEVELS = [0, 1000, 2500, 5000, 10000]
const LEVEL_NAMES = ['Starter', 'Walker', 'Strider', 'Pacer', 'Legend']

export default function RewardsPage() {
  const { points, claimed } = useAppState()
  const { claimStreak, toast } = useApp()
  const { derived, loading, error, reload } = useStats()

  if (error) return <ErrorState message={error} onRetry={reload} />
  if (loading || !derived) return <div className="space-y-6"><Skeleton className="h-44" /><Skeleton className="h-64" /></div>

  const { streak, badges, lifetime } = derived
  const lvl = LEVELS.reduce((acc, t, i) => (points >= t ? i : acc), 0)
  const next = LEVELS[lvl + 1]
  const lvlProgress = next ? ((points - LEVELS[lvl]) / (next - LEVELS[lvl])) * 100 : 100
  const earned = badges.filter((b) => b.earned).length

  return (
    <div className="space-y-6">
      <PageHeader title="Rewards" subtitle="Points, badges and milestones for staying consistent." demo />

      {/* Points */}
      <Card className="relative overflow-hidden bg-gradient-to-br from-dark to-[#3f7545] text-white">
        <div className="pointer-events-none absolute -right-10 -top-10 h-48 w-48 rounded-full bg-lime/20 blur-2xl" />
        <div className="relative flex flex-wrap items-center justify-between gap-6">
          <div>
            <p className="flex items-center gap-1.5 text-sm font-semibold text-white/75"><Sparkles size={15} /> Your points</p>
            <p className="mt-1 text-5xl font-extrabold tracking-tight">{fmt(points)}</p>
            <p className="mt-1 text-sm text-white/75">Level: <strong className="text-white">{LEVEL_NAMES[lvl]}</strong> · {earned} of {badges.length} badges</p>
          </div>
          <div className="w-full max-w-sm">
            <div className="mb-1.5 flex justify-between text-xs font-semibold text-white/80">
              <span>{LEVEL_NAMES[lvl]}</span>
              <span>{next ? `${fmt(next - points)} pts to ${LEVEL_NAMES[lvl + 1]}` : 'Max level'}</span>
            </div>
            <div className="h-2.5 overflow-hidden rounded-full bg-white/20">
              <div className="h-full rounded-full bg-lime transition-[width] duration-700" style={{ width: `${lvlProgress}%` }} />
            </div>
          </div>
        </div>
      </Card>

      {/* Streak rewards */}
      <Card>
        <CardHeader title="Streak rewards" subtitle={`Current streak: ${streak} ${streak === 1 ? 'day' : 'days'} at goal`} />
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
          {STREAK_REWARDS.map((r) => {
            const reached = streak >= r.days
            const done = claimed.includes(r.days)
            return (
              <li key={r.days} className={cx('flex flex-col items-center rounded-2xl border p-4 text-center', reached ? 'border-lime bg-soft/60' : 'border-line')}>
                <p className="text-3xl font-extrabold text-dark">{r.days}</p>
                <p className="text-xs font-semibold text-muted">day streak</p>
                <p className="mt-2 text-sm font-bold">{r.label}</p>
                <p className="text-xs text-primary font-bold">+{r.points} pts</p>
                <div className="mt-3 w-full">
                  {done ? (
                    <Pill><Check size={12} /> Claimed</Pill>
                  ) : reached ? (
                    <Button size="sm" className="w-full" onClick={() => { claimStreak(r.days, r.points); toast(`+${r.points} points claimed`) }}>Claim</Button>
                  ) : (
                    <>
                      <ProgressBar value={(streak / r.days) * 100} label={`${r.label} progress`} />
                      <p className="mt-1 text-[11px] text-muted">{r.days - streak} more {r.days - streak === 1 ? 'day' : 'days'}</p>
                    </>
                  )}
                </div>
              </li>
            )
          })}
        </ul>
      </Card>

      {/* Badges */}
      <Card>
        <CardHeader title="Achievement badges" subtitle={`${earned} earned`} />
        <ul className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
          {badges.map((b) => {
            const Icon = getIcon(b.icon)
            return (
              <li key={b.id} className={cx('flex flex-col items-center rounded-2xl border p-4 text-center', b.earned ? 'border-lime bg-soft/60' : 'border-line bg-[#FAFBF9]')}>
                <span className={cx('relative mb-2 flex h-14 w-14 items-center justify-center rounded-full', b.earned ? 'bg-gradient-to-br from-lime to-primary text-white shadow-sm' : 'bg-[#EEF0EC] text-[#A9B3A4]')}>
                  <Icon size={26} />
                  {!b.earned && <Lock size={13} className="absolute -bottom-0.5 -right-0.5 rounded-full bg-white p-0.5 text-muted" />}
                </span>
                <p className="text-sm font-bold">{b.name}</p>
                <p className="text-xs text-muted">{b.description}</p>
                {!b.earned && <ProgressBar value={b.progress * 100} className="mt-2 h-1.5" label={`${b.name} progress`} />}
              </li>
            )
          })}
        </ul>
      </Card>

      {/* Milestones */}
      <Card>
        <CardHeader title="Milestones" subtitle={`${fmt(lifetime)} lifetime steps (demo)`} />
        <ul className="space-y-4">
          {MILESTONES.map((m) => {
            const p = Math.min(100, (lifetime / m.target) * 100)
            return (
              <li key={m.id}>
                <div className="mb-1.5 flex items-center justify-between text-sm">
                  <span className="font-bold">{m.label}</span>
                  {p >= 100 ? <Pill><Check size={12} /> Reached</Pill> : <span className="text-muted">{fmt(lifetime)} / {fmt(m.target)}</span>}
                </div>
                <ProgressBar value={p} label={m.label} />
              </li>
            )
          })}
        </ul>
      </Card>
    </div>
  )
}
