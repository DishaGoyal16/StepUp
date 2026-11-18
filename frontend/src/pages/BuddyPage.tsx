import { useMemo, useState } from 'react'
import { Check, Clock, Footprints, MapPin, Search, UserPlus } from 'lucide-react'
import { Avatar, Button, Card, EmptyState, ErrorState, PageHeader, Pill, Skeleton, Toggle, cx, inputClass } from '../components/ui'
import { useApp, useAppState } from '../hooks/useApp'
import { useAsync } from '../hooks/useAsync'
import { fmt } from '../lib/format'
import { communityService } from '../services/communityService'
import type { SessionType } from '../types'

const ACTIVITIES: ('All' | SessionType)[] = ['All', 'Walk', 'Run', 'Hike', 'Cycle']

export default function BuddyPage() {
  const { user, requested } = useAppState()
  const { toggleBuddy, toast } = useApp()
  const { data, loading, error, reload } = useAsync(() => communityService.getBuddies(), [])
  const [query, setQuery] = useState('')
  const [activity, setActivity] = useState<(typeof ACTIVITIES)[number]>('All')
  const [nearby, setNearby] = useState(false)

  const list = useMemo(() => {
    const q = query.trim().toLowerCase()
    return (data ?? [])
      .filter((b) => (activity === 'All' ? true : b.activity === activity))
      .filter((b) => (nearby && user.city ? b.city.toLowerCase() === user.city.toLowerCase() : true))
      .filter((b) => !q || b.name.toLowerCase().includes(q) || b.city.toLowerCase().includes(q))
      .sort((a, b) => b.match - a.match)
  }, [data, query, activity, nearby, user.city])

  if (error) return <ErrorState message={error} onRetry={reload} />

  return (
    <div>
      <PageHeader title="Sport Buddy" subtitle="Find walking and running partners with a similar pace." demo />

      <Card className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-center">
        <div className="relative flex-1">
          <Search size={17} className="absolute left-4 top-1/2 -translate-y-1/2 text-muted" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label="Search buddies by name or city"
            placeholder="Search by name or city"
            className={`${inputClass} pl-11`}
          />
        </div>
        <div className="flex flex-wrap gap-2" role="group" aria-label="Activity filter">
          {ACTIVITIES.map((a) => (
            <button
              key={a}
              aria-pressed={activity === a}
              onClick={() => setActivity(a)}
              className={cx('rounded-full px-4 py-2 text-sm font-semibold transition', activity === a ? 'bg-primary text-white' : 'bg-soft text-dark hover:bg-lime/30')}
            >
              {a}
            </button>
          ))}
        </div>
        <label className="flex items-center gap-2 text-sm font-semibold text-muted">
          Near me{user.city ? ` (${user.city})` : ''}
          <Toggle checked={nearby} onChange={setNearby} label="Only show buddies in my city" />
        </label>
      </Card>

      {nearby && !user.city && (
        <p className="mb-4 rounded-2xl bg-[#FFF8E6] p-3 text-sm text-[#7a5a10]">Add your city in Profile & Settings to filter by location.</p>
      )}

      {loading ? (
        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-64" />)}</div>
      ) : list.length === 0 ? (
        <EmptyState
          title="No buddies match"
          body="Try a different activity or clear the search."
          action={<Button size="sm" variant="ghost" onClick={() => { setQuery(''); setActivity('All'); setNearby(false) }}>Clear filters</Button>}
        />
      ) : (
        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
          {list.map((b) => {
            const sent = requested.includes(b.id)
            return (
              <Card key={b.id} className="flex flex-col">
                <div className="flex items-start gap-3">
                  <Avatar name={b.name} size={52} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-lg font-extrabold">{b.name}</p>
                    <p className="flex items-center gap-1 text-sm text-muted"><MapPin size={13} />{b.city}</p>
                  </div>
                  <Pill>{b.match}% match</Pill>
                </div>
                <p className="mt-3 flex-1 text-sm text-muted">{b.bio}</p>
                <dl className="mt-4 grid grid-cols-2 gap-2 text-sm">
                  <div className="rounded-xl bg-[#F7F9F5] p-2.5">
                    <dt className="flex items-center gap-1 text-[11px] font-semibold text-muted"><Footprints size={11} />Avg steps</dt>
                    <dd className="font-extrabold">{fmt(b.avgSteps)}</dd>
                  </div>
                  <div className="rounded-xl bg-[#F7F9F5] p-2.5">
                    <dt className="text-[11px] font-semibold text-muted">{b.activity} pace</dt>
                    <dd className="font-extrabold">{b.pace}</dd>
                  </div>
                </dl>
                <p className="mt-3 flex items-center gap-1.5 text-xs font-semibold text-muted"><Clock size={13} />{b.availability}</p>
                <Button
                  className="mt-4 w-full"
                  variant={sent ? 'soft' : 'primary'}
                  aria-pressed={sent}
                  onClick={() => {
                    toggleBuddy(b.id)
                    toast(sent ? `Request to ${b.name} cancelled` : `Request sent to ${b.name} (demo)`)
                  }}
                >
                  {sent ? <><Check size={16} /> Requested · tap to cancel</> : <><UserPlus size={16} /> Connect</>}
                </Button>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
