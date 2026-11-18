import { useState } from 'react'
import { Crown, FastForward, Plus, Swords, Trash2 } from 'lucide-react'
import { BattleBars } from '../components/charts'
import { Avatar, Button, Card, DemoBadge, EmptyState, Field, Modal, PageHeader, Pill, ProgressBar, Segmented, cx, inputClass } from '../components/ui'
import { useApp, useAppState } from '../hooks/useApp'
import { useAsync } from '../hooks/useAsync'
import { fmt } from '../lib/format'
import { communityService } from '../services/communityService'

export default function BattlesPage() {
  const { battles } = useAppState()
  const { createBattle, simulateBattleDay, removeBattle, toast } = useApp()
  const friends = useAsync(() => communityService.getFriends(), [])
  const [open, setOpen] = useState(false)

  // form state
  const [name, setName] = useState('')
  const [picked, setPicked] = useState<string[]>([])
  const [days, setDays] = useState<'3' | '5' | '7'>('7')
  const [errors, setErrors] = useState<{ name?: string; picked?: string }>({})

  function submit() {
    const next: typeof errors = {}
    if (name.trim().length < 3) next.name = 'Give your battle a name (3+ characters).'
    if (picked.length === 0) next.picked = 'Pick at least one opponent.'
    setErrors(next)
    if (Object.keys(next).length) return
    createBattle(name.trim(), (friends.data ?? []).filter((f) => picked.includes(f.id)), Number(days))
    toast(`Battle “${name.trim()}” created`)
    setOpen(false)
    setName('')
    setPicked([])
    setDays('7')
  }

  return (
    <div>
      <PageHeader
        title="Step Battles"
        subtitle="Challenge friends to a head-to-head step race."
        demo
        action={<Button onClick={() => setOpen(true)}><Plus size={17} /> Create battle</Button>}
      />

      {battles.length === 0 ? (
        <EmptyState
          title="No battles yet"
          body="Start one and see who racks up the most steps."
          action={<Button onClick={() => setOpen(true)}><Swords size={16} /> Create your first battle</Button>}
        />
      ) : (
        <div className="space-y-6">
          {battles.map((b) => {
            const finished = b.daysElapsed >= b.durationDays
            const ranked = [...b.participants].sort((x, y) => y.steps - x.steps)
            const leader = ranked[0]
            const progress = (b.daysElapsed / b.durationDays) * 100
            const anySteps = ranked.some((p) => p.steps > 0)
            return (
              <Card key={b.id}>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <h2 className="text-xl font-extrabold">{b.name}</h2>
                      <Pill tone={finished ? 'gray' : 'green'}>{finished ? 'Completed' : 'Active'}</Pill>
                    </div>
                    <p className="mt-1 text-sm text-muted">{b.participants.length} participants · {b.durationDays}-day battle</p>
                  </div>
                  <div className="flex gap-2">
                    {!finished && (
                      <Button
                        variant="soft"
                        size="sm"
                        onClick={() => {
                          simulateBattleDay(b.id)
                          toast('Simulated one demo day for all participants')
                        }}
                      >
                        <FastForward size={15} /> Simulate day
                      </Button>
                    )}
                    <Button
                      variant="ghost"
                      size="sm"
                      aria-label={`Delete ${b.name}`}
                      onClick={() => {
                        removeBattle(b.id)
                        toast('Battle removed')
                      }}
                    >
                      <Trash2 size={15} />
                    </Button>
                  </div>
                </div>

                <div className="mt-4">
                  <div className="mb-1.5 flex justify-between text-sm">
                    <span className="font-semibold">Battle progress</span>
                    <span className="text-muted">Day {Math.min(b.daysElapsed, b.durationDays)} of {b.durationDays}</span>
                  </div>
                  <ProgressBar value={progress} label="Battle progress" />
                </div>

                {finished && anySteps && (
                  <div className="mt-4 flex items-center gap-3 rounded-2xl bg-soft px-4 py-3">
                    <Crown className="text-primary" size={20} />
                    <p className="text-sm font-semibold text-dark">
                      {leader.isYou ? 'You won this battle!' : `${leader.name} won this battle.`} <span className="font-normal">({fmt(leader.steps)} steps)</span>
                    </p>
                  </div>
                )}

                <div className="mt-5 grid items-center gap-6 lg:grid-cols-2">
                  <div>
                    <p className="mb-1 text-sm font-bold">Participant comparison</p>
                    {anySteps ? <BattleBars participants={b.participants} /> : (
                      <p className="rounded-2xl bg-[#F7F9F5] p-5 text-sm text-muted">No steps counted yet. Use “Simulate day” to preview how the comparison looks.</p>
                    )}
                  </div>
                  <div>
                    <p className="mb-2 flex items-center gap-2 text-sm font-bold">Rankings <DemoBadge /></p>
                    <ol className="space-y-2">
                      {ranked.map((p, i) => (
                        <li key={p.id} className={cx('flex items-center gap-3 rounded-2xl border p-3', p.isYou ? 'border-lime bg-soft/60' : 'border-line')}>
                          <span className={cx('flex h-7 w-7 items-center justify-center rounded-full text-xs font-extrabold', i === 0 && anySteps ? 'bg-primary text-white' : 'bg-[#F0F2EE] text-muted')}>{i + 1}</span>
                          <Avatar name={p.isYou ? 'You' : p.name} size={34} />
                          <span className="flex-1 truncate font-semibold">{p.name}</span>
                          <div className="text-right">
                            <p className="font-extrabold">{fmt(p.steps)}</p>
                            {i > 0 && leader.steps > p.steps && <p className="text-[11px] text-muted">−{fmt(leader.steps - p.steps)}</p>}
                          </div>
                        </li>
                      ))}
                    </ol>
                  </div>
                </div>
              </Card>
            )
          })}
        </div>
      )}

      <Modal open={open} onClose={() => setOpen(false)} title="Create a step battle">
        <div className="space-y-5">
          <Field label="Battle name" error={errors.name}>
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={40} className={inputClass} placeholder="e.g. Friday Face-off" />
          </Field>

          <div>
            <p className="mb-1.5 text-sm font-semibold">Opponents</p>
            <div className="flex flex-wrap gap-2">
              {friends.data?.map((f) => {
                const on = picked.includes(f.id)
                return (
                  <button
                    key={f.id}
                    type="button"
                    aria-pressed={on}
                    onClick={() => setPicked((p) => (on ? p.filter((x) => x !== f.id) : [...p, f.id]))}
                    className={cx('flex items-center gap-2 rounded-full border py-1 pl-1 pr-3.5 text-sm font-semibold transition', on ? 'border-primary bg-soft text-dark' : 'border-line hover:bg-[#F7F9F5]')}
                  >
                    <Avatar name={f.name} size={26} /> {f.name}
                  </button>
                )
              })}
            </div>
            {errors.picked && <p className="mt-1 text-xs font-medium text-red-600">{errors.picked}</p>}
          </div>

          <div>
            <p className="mb-1.5 text-sm font-semibold">Duration</p>
            <Segmented label="Battle duration" value={days} onChange={setDays} options={[{ value: '3', label: '3 days' }, { value: '5', label: '5 days' }, { value: '7', label: '7 days' }]} />
          </div>

          <p className="rounded-2xl bg-[#FFF8E6] p-3 text-xs text-[#7a5a10]">
            Demo mode: opponents are sample friends, and there's no live step feed. Use “Simulate day” on the battle to preview results.
          </p>

          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
            <Button onClick={submit}>Start battle</Button>
          </div>
        </div>
      </Modal>
    </div>
  )
}
