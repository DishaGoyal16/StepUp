import { useMemo, useState } from 'react'
import { Crown, Flame, TrendingUp } from 'lucide-react'
import { Avatar, Card, ErrorState, PageHeader, Pill, Segmented, Skeleton, cx } from '../components/ui'
import { useAppState } from '../hooks/useApp'
import { useAsync } from '../hooks/useAsync'
import { useStats } from '../hooks/useStats'
import { fmt } from '../lib/format'
import { sum } from '../lib/stats'
import { communityService } from '../services/communityService'
import type { LeaderboardEntry } from '../types'

type Period = 'weekly' | 'monthly'

export default function LeaderboardPage() {
  const { user } = useAppState()
  const { derived } = useStats()
  const board = useAsync(() => communityService.getLeaderboard(), [])
  const [period, setPeriod] = useState<Period>('weekly')

  const ranked = useMemo(() => {
    if (!board.data || !derived) return null
    const me: LeaderboardEntry = {
      id: user.id,
      name: user.name,
      city: user.city || 'Somewhere',
      weekly: sum(derived.days.slice(-7)),
      monthly: sum(derived.days.slice(-30)),
      streak: derived.streak,
      isYou: true,
    }
    return [...board.data, me].sort((a, b) => b[period] - a[period])
  }, [board.data, derived, user, period])

  if (board.error) return <ErrorState message={board.error} onRetry={board.reload} />

  const myIndex = ranked?.findIndex((r) => r.isYou) ?? -1
  const me = ranked?.[myIndex]
  const ahead = myIndex > 0 ? ranked![myIndex - 1] : null

  return (
    <div className="space-y-6">
      <PageHeader
        title="Leaderboard"
        subtitle="See how you stack up this week."
        demo
        action={
          <Segmented<Period>
            label="Leaderboard period"
            value={period}
            onChange={setPeriod}
            options={[{ value: 'weekly', label: 'Weekly' }, { value: 'monthly', label: 'Monthly' }]}
          />
        }
      />

      {!ranked || !me ? (
        <div className="space-y-4"><Skeleton className="h-28" /><Skeleton className="h-64" /></div>
      ) : (
        <>
          {/* Your rank */}
          <Card className="flex flex-wrap items-center gap-5 bg-gradient-to-r from-soft to-white">
            <div className="flex h-20 w-20 flex-col items-center justify-center rounded-3xl bg-primary text-white shadow-md">
              <span className="text-[11px] font-bold uppercase tracking-wider opacity-80">Rank</span>
              <span className="text-3xl font-extrabold leading-none">#{myIndex + 1}</span>
            </div>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold text-muted">Your {period} rank</p>
              <p className="text-2xl font-extrabold">{fmt(me[period])} steps</p>
              <p className="text-sm text-muted">
                {ahead ? `${fmt(ahead[period] - me[period])} steps behind ${ahead.name}` : "You're leading the board — keep it up!"}
              </p>
            </div>
            <Pill><Flame size={13} /> {me.streak}-day streak</Pill>
          </Card>

          {/* Podium */}
          <div className="grid grid-cols-3 items-end gap-3 sm:gap-5">
            {[1, 0, 2].map((idx) => {
              const e = ranked[idx]
              const h = idx === 0 ? 'h-40' : idx === 1 ? 'h-32' : 'h-28'
              return (
                <div key={e.id} className="flex flex-col items-center text-center">
                  {idx === 0 && <Crown className="mb-1 text-primary" size={22} />}
                  <Avatar name={e.name} size={idx === 0 ? 68 : 56} ring />
                  <p className="mt-2 w-full truncate text-sm font-bold">{e.isYou ? 'You' : e.name}</p>
                  <p className="text-xs font-semibold text-muted">{fmt(e[period])}</p>
                  <div className={cx('mt-2 flex w-full items-start justify-center rounded-t-3xl pt-3 text-2xl font-extrabold', h, idx === 0 ? 'bg-gradient-to-b from-lime to-primary text-white' : 'bg-soft text-dark')}>
                    {idx + 1}
                  </div>
                </div>
              )
            })}
          </div>

          {/* Full list */}
          <Card className="p-2 sm:p-3">
            <ol>
              {ranked.map((e, i) => (
                <li
                  key={e.id}
                  className={cx('flex items-center gap-3 rounded-2xl px-3 py-3 sm:gap-4 sm:px-4', e.isYou ? 'bg-soft ring-1 ring-lime' : 'hover:bg-[#F7F9F5]')}
                >
                  <span className="w-7 text-center text-sm font-extrabold text-muted">{i + 1}</span>
                  <Avatar name={e.name} size={40} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-bold">{e.name} {e.isYou && <span className="ml-1 text-xs font-bold text-primary">(you)</span>}</p>
                    <p className="truncate text-xs text-muted">{e.city}</p>
                  </div>
                  <span className="hidden items-center gap-1 text-xs font-semibold text-muted sm:flex"><Flame size={13} className="text-primary" />{e.streak}d</span>
                  <div className="text-right">
                    <p className="font-extrabold">{fmt(e[period])}</p>
                    <p className="flex items-center justify-end gap-1 text-[11px] text-muted"><TrendingUp size={11} />steps</p>
                  </div>
                </li>
              ))}
            </ol>
          </Card>
        </>
      )}
    </div>
  )
}
