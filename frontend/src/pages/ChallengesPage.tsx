import { useState } from 'react'
import { CalendarClock, Check, Gift, Users } from 'lucide-react'
import { getIcon } from '../components/icons'
import { Button, Card, EmptyState, ErrorState, PageHeader, Pill, ProgressBar, Segmented, Skeleton } from '../components/ui'
import { useApp, useAppState } from '../hooks/useApp'
import { useAsync } from '../hooks/useAsync'
import { useStats } from '../hooks/useStats'
import { fmt } from '../lib/format'
import { pct } from '../lib/stats'
import { communityService } from '../services/communityService'

type Filter = 'all' | 'joined' | 'open'

export default function ChallengesPage() {
  const state = useAppState()
  const { joinChallenge, leaveChallenge, toast } = useApp()
  const { derived } = useStats()
  const { data, loading, error, reload } = useAsync(() => communityService.getChallenges(), [])
  const [filter, setFilter] = useState<Filter>('all')

  if (error) return <ErrorState message={error} onRetry={reload} />

  const list = (data ?? []).filter((c) =>
    filter === 'all' ? true : filter === 'joined' ? c.id in state.joined : !(c.id in state.joined),
  )

  return (
    <div>
      <PageHeader
        title="Challenges"
        subtitle="Set a target, join the crowd, earn points."
        demo
        action={
          <Segmented<Filter>
            label="Filter challenges"
            value={filter}
            onChange={setFilter}
            options={[
              { value: 'all', label: 'All' },
              { value: 'joined', label: `Joined (${Object.keys(state.joined).length})` },
              { value: 'open', label: 'Available' },
            ]}
          />
        }
      />

      {loading ? (
        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-64" />)}</div>
      ) : list.length === 0 ? (
        <EmptyState
          title={filter === 'joined' ? "You haven't joined any challenges" : 'No more challenges to join'}
          body={filter === 'joined' ? 'Pick one from the Available tab and start stepping.' : "You've joined everything — nice work."}
          action={filter === 'joined' ? <Button size="sm" onClick={() => setFilter('open')}>See available</Button> : undefined}
        />
      ) : (
        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
          {list.map((c) => {
            const Icon = getIcon(c.icon)
            const isJoined = c.id in state.joined
            const steps = state.joined[c.id] ?? 0
            const p = pct(steps, c.targetSteps)
            const done = isJoined && steps >= c.targetSteps
            return (
              <Card key={c.id} className="flex flex-col">
                <div className="flex items-start justify-between">
                  <span className="flex h-12 w-12 items-center justify-center rounded-2xl bg-soft text-primary"><Icon size={24} /></span>
                  <Pill tone={c.difficulty === 'Hard' ? 'amber' : c.difficulty === 'Easy' ? 'green' : 'gray'}>{c.difficulty}</Pill>
                </div>
                <h3 className="mt-4 text-lg font-extrabold">{c.title}</h3>
                <p className="mt-1 flex-1 text-sm text-muted">{c.description}</p>

                <dl className="mt-4 grid grid-cols-3 gap-2 text-center">
                  <div className="rounded-xl bg-[#F7F9F5] p-2">
                    <dt className="text-[11px] font-semibold text-muted">Target</dt>
                    <dd className="text-sm font-extrabold">{c.targetSteps >= 1000 ? `${c.targetSteps / 1000}K` : c.targetSteps}</dd>
                  </div>
                  <div className="rounded-xl bg-[#F7F9F5] p-2">
                    <dt className="flex items-center justify-center gap-1 text-[11px] font-semibold text-muted"><CalendarClock size={11} />Duration</dt>
                    <dd className="text-sm font-extrabold">{c.durationDays}d</dd>
                  </div>
                  <div className="rounded-xl bg-[#F7F9F5] p-2">
                    <dt className="flex items-center justify-center gap-1 text-[11px] font-semibold text-muted"><Gift size={11} />Reward</dt>
                    <dd className="text-sm font-extrabold">{c.rewardPoints}</dd>
                  </div>
                </dl>

                {isJoined && (
                  <div className="mt-4">
                    <div className="mb-1.5 flex justify-between text-xs">
                      <span className="font-semibold">{fmt(steps)} / {fmt(c.targetSteps)} steps</span>
                      <span className="font-extrabold text-primary">{p}%</span>
                    </div>
                    <ProgressBar value={p} label={`${c.title} progress`} />
                  </div>
                )}

                <div className="mt-5 flex items-center justify-between gap-2">
                  <span className="flex items-center gap-1.5 text-xs font-semibold text-muted"><Users size={14} />{fmt(c.participants + (isJoined ? 1 : 0))} joined</span>
                  {done ? (
                    <Pill><Check size={13} /> Completed</Pill>
                  ) : isJoined ? (
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => {
                        leaveChallenge(c.id)
                        toast(`Left “${c.title}”`)
                      }}
                    >
                      Leave
                    </Button>
                  ) : (
                    <Button
                      size="sm"
                      onClick={() => {
                        joinChallenge(c.id, derived?.today.steps ?? 0)
                        toast(`Joined “${c.title}” — today's steps count toward it`)
                      }}
                    >
                      Join challenge
                    </Button>
                  )}
                </div>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
