import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Database, LogOut, RotateCcw, Save } from 'lucide-react'
import { Avatar, Button, Card, CardHeader, DemoBadge, Field, Modal, PageHeader, Segmented, Toggle, inputClass } from '../components/ui'
import { useApp, useAppState } from '../hooks/useApp'
import { fmt } from '../lib/format'

export default function ProfilePage() {
  const { user, prefs } = useAppState()
  const { updateUser, updatePrefs, logout, resetDemo, toast } = useApp()
  const navigate = useNavigate()

  const [name, setName] = useState(user.name)
  const [city, setCity] = useState(user.city)
  const [bio, setBio] = useState(user.bio)
  const [goal, setGoal] = useState(user.dailyGoal)
  const [nameErr, setNameErr] = useState<string | null>(null)
  const [confirmReset, setConfirmReset] = useState(false)

  const profileDirty = name !== user.name || city !== user.city || bio !== user.bio
  const goalDirty = goal !== user.dailyGoal

  function saveProfile() {
    if (name.trim().length < 2) return setNameErr('Name must be at least 2 characters.')
    setNameErr(null)
    updateUser({ name: name.trim(), city: city.trim(), bio: bio.trim() })
    toast('Profile saved')
  }

  function saveGoal() {
    const g = Math.max(1000, Math.min(50000, Math.round(goal / 100) * 100))
    setGoal(g)
    updateUser({ dailyGoal: g })
    toast(`Daily goal set to ${fmt(g)} steps`)
  }

  return (
    <div className="space-y-6">
      <PageHeader title="Profile & Settings" subtitle="Manage your info, goal and preferences." />

      <Card className="flex flex-wrap items-center gap-5">
        <Avatar name={user.name} size={72} />
        <div className="min-w-0 flex-1">
          <p className="truncate text-2xl font-extrabold">{user.name}</p>
          <p className="truncate text-muted">{user.email}</p>
          <p className="mt-1 text-xs font-semibold text-muted">Member since {new Date(user.joinedAt).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}</p>
        </div>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader title="User information" />
          <div className="space-y-4">
            <Field label="Full name" error={nameErr}>
              <input value={name} onChange={(e) => setName(e.target.value)} className={inputClass} maxLength={60} />
            </Field>
            <Field label="Email">
              <input value={user.email} readOnly className={`${inputClass} cursor-not-allowed bg-[#F7F9F5] text-muted`} />
            </Field>
            <Field label="City">
              <input value={city} onChange={(e) => setCity(e.target.value)} className={inputClass} maxLength={60} placeholder="Used for Sport Buddy matches" />
            </Field>
            <Field label="Bio">
              <textarea value={bio} onChange={(e) => setBio(e.target.value)} rows={3} maxLength={160} className={inputClass} />
            </Field>
            <Button onClick={saveProfile} disabled={!profileDirty}><Save size={16} /> Save changes</Button>
          </div>
        </Card>

        <div className="space-y-6">
          <Card>
            <CardHeader title="Daily step goal" subtitle="Drives your rings, streaks and rewards." />
            <div className="flex items-end justify-between">
              <p className="text-4xl font-extrabold text-primary">{fmt(goal)}</p>
              <p className="text-sm text-muted">steps / day</p>
            </div>
            <input
              type="range"
              min={2000}
              max={30000}
              step={500}
              value={Math.min(goal, 30000)}
              onChange={(e) => setGoal(Number(e.target.value))}
              aria-label="Daily step goal"
              className="mt-4 w-full accent-[#70A83B]"
            />
            <div className="mt-1 flex justify-between text-xs text-muted"><span>2,000</span><span>30,000</span></div>
            <div className="mt-4 flex gap-2">
              {[6000, 8000, 10000, 12000].map((g) => (
                <button key={g} onClick={() => setGoal(g)} className="rounded-full bg-soft px-3 py-1.5 text-xs font-bold text-dark hover:bg-lime/30">{fmt(g)}</button>
              ))}
            </div>
            <Button className="mt-5" onClick={saveGoal} disabled={!goalDirty}>Save goal</Button>
          </Card>

          <Card>
            <CardHeader title="Preferences" />
            <div className="space-y-4">
              <div className="flex items-center justify-between gap-4">
                <span className="font-semibold">Distance units</span>
                <Segmented
                  label="Distance units"
                  value={user.units}
                  onChange={(u) => { updateUser({ units: u }); toast(`Units set to ${u}`) }}
                  options={[{ value: 'km', label: 'km' }, { value: 'mi', label: 'miles' }]}
                />
              </div>
              {([
                ['daily', 'Daily goal reminder'],
                ['battles', 'Step battle updates'],
                ['weekly', 'Weekly summary'],
              ] as const).map(([key, label]) => (
                <div key={key} className="flex items-center justify-between gap-4">
                  <span className="font-semibold">{label}</span>
                  <Toggle checked={prefs[key]} onChange={(v) => updatePrefs({ [key]: v })} label={label} />
                </div>
              ))}
            </div>
          </Card>
        </div>
      </div>

      <Card>
        <CardHeader title="Account" />
        <div className="flex items-start gap-3 rounded-2xl bg-[#F7F9F5] p-4">
          <Database size={20} className="mt-0.5 shrink-0 text-primary" />
          <div className="text-sm">
            <p className="flex items-center gap-2 font-bold">Activity source <DemoBadge /></p>
            <p className="mt-1 text-muted">No real activity source is connected. The dashboard is showing sample data. A source can be wired in through the activity service later.</p>
          </div>
        </div>
        <div className="mt-5 flex flex-wrap gap-3">
          <Button variant="ghost" onClick={() => setConfirmReset(true)}><RotateCcw size={16} /> Reset demo data</Button>
          <Button variant="danger" onClick={() => { logout(); toast('Signed out'); navigate('/login') }}><LogOut size={16} /> Log out</Button>
        </div>
      </Card>

      <Modal open={confirmReset} onClose={() => setConfirmReset(false)} title="Reset demo data?">
        <p className="text-sm text-muted">This restores challenges, battles, buddy requests, points and claimed rewards to their starting demo state. Your profile stays as it is.</p>
        <div className="mt-5 flex justify-end gap-2">
          <Button variant="ghost" onClick={() => setConfirmReset(false)}>Cancel</Button>
          <Button onClick={() => { resetDemo(); setConfirmReset(false); toast('Demo data reset') }}>Reset</Button>
        </div>
      </Modal>
    </div>
  )
}
