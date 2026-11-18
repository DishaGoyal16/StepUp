import { useMemo, useState } from 'react'
import { CalendarDays, Footprints, Medal, TrendingUp } from 'lucide-react'
import { TrendAreaChart, WeeklyBarChart } from '../components/charts'
import { StatCard } from '../components/StatCard'
import { Button, Card, CardHeader, EmptyState, ErrorState, PageHeader, Pill, Segmented, Skeleton, Toggle } from '../components/ui'
import { useAppState } from '../hooks/useApp'
import { useStats } from '../hooks/useStats'
import { distance, fmt, shortDate, shortDay } from '../lib/format'
import { average, sum } from '../lib/stats'

type Range = '7' | '30' | '90'
const RANGE_LABEL: Record<Range, string> = { '7': 'Week', '30': 'Month', '90': '3 months' }
const PAGE = 14

export default function ActivityPage() {
  const { user } = useAppState()
  const { derived, loading, error, reload } = useStats()
  const [range, setRange] = useState<Range>('7')
  const [goalOnly, setGoalOnly] = useState(false)
  const [shown, setShown] = useState(PAGE)

  const slice = useMemo(() => (derived ? derived.days.slice(-Number(range)) : []), [derived, range])
  const rows = useMemo(() => {
    const r = [...slice].reverse()
    return goalOnly ? r.filter((d) => d.steps >= user.dailyGoal) : r
  }, [slice, goalOnly, user.dailyGoal])

  if (error) return <ErrorState message={error} onRetry={reload} />

  const best = slice.reduce<(typeof slice)[number] | null>((b, d) => (!b || d.steps > b.steps ? d : b), null)

  return (
    <div className="space-y-6">
      <PageHeader
        title="My Activity"
        subtitle="Daily steps, trends and history."
        demo
        action={
          <Segmented
            label="Date range"
            value={range}
            onChange={(v) => {
              setRange(v)
              setShown(PAGE)
            }}
            options={(Object.keys(RANGE_LABEL) as Range[]).map((v) => ({ value: v, label: RANGE_LABEL[v] }))}
          />
        }
      />

      {loading || !derived ? (
        <div className="space-y-6">
          <Skeleton className="h-32" />
          <Skeleton className="h-80" />
        </div>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <StatCard icon={Footprints} label="Today" value={fmt(derived.today.steps)} note={`goal ${fmt(user.dailyGoal)}`} />
            <StatCard icon={TrendingUp} label="Average / day" value={fmt(average(slice))} note={`last ${range} days`} />
            <StatCard icon={Medal} label="Best day" value={best ? fmt(best.steps) : '—'} note={best ? shortDate(best.date) : undefined} />
            <StatCard icon={CalendarDays} label="Total steps" value={fmt(sum(slice))} note={distance(sum(slice, 'distanceKm'), user.units) + ' est.'} />
          </div>

          <Card>
            <CardHeader
              title={range === '7' ? 'Weekly activity' : range === '30' ? 'Monthly activity' : 'Last 3 months'}
              subtitle="Dashed line marks your daily goal"
            />
            {range === '7' ? <WeeklyBarChart data={slice} goal={user.dailyGoal} height={280} /> : <TrendAreaChart data={slice} goal={user.dailyGoal} height={300} />}
          </Card>

          <Card>
            <CardHeader
              title="Activity history"
              subtitle={`${rows.length} ${rows.length === 1 ? 'day' : 'days'}`}
              action={
                <label className="flex items-center gap-2 text-sm font-semibold text-muted">
                  Goal days only
                  <Toggle checked={goalOnly} onChange={(v) => { setGoalOnly(v); setShown(PAGE) }} label="Show only days that met the goal" />
                </label>
              }
            />
            {rows.length === 0 ? (
              <EmptyState title="No matching days" body="No days in this range reached your goal yet. Try a longer range." />
            ) : (
              <>
                <ul className="divide-y divide-line">
                  {rows.slice(0, shown).map((d, i) => {
                    const met = d.steps >= user.dailyGoal
                    const isToday = d.date === derived.today.date
                    return (
                      <li key={d.date} className="flex items-center gap-3 py-3.5">
                        <div className="w-14 shrink-0 text-center">
                          <p className="text-xs font-bold uppercase text-muted">{shortDay(d.date)}</p>
                          <p className="text-sm font-extrabold">{shortDate(d.date)}</p>
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="font-extrabold">{fmt(d.steps)} <span className="text-sm font-medium text-muted">steps</span></p>
                          <p className="text-xs text-muted">
                            {distance(d.distanceKm, user.units)} · {fmt(d.calories)} kcal · {d.activeMinutes} min active
                          </p>
                        </div>
                        {isToday && i === 0 ? <Pill tone="amber">In progress</Pill> : met ? <Pill>Goal met</Pill> : <Pill tone="gray">{Math.round((d.steps / user.dailyGoal) * 100)}%</Pill>}
                      </li>
                    )
                  })}
                </ul>
                {shown < rows.length && (
                  <div className="mt-4 text-center">
                    <Button variant="ghost" size="sm" onClick={() => setShown((s) => s + PAGE)}>
                      Show more
                    </Button>
                  </div>
                )}
              </>
            )}
          </Card>
        </>
      )}
    </div>
  )
}
