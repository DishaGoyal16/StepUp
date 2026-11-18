import { Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { fmt, shortDate, shortDay } from '../lib/format'
import type { BattleParticipant, DayActivity } from '../types'

const GRID = '#E8EDE5'
const AXIS = '#7D8878'

function StepTooltip({ active, payload, label }: { active?: boolean; payload?: { value: number }[]; label?: string }) {
  if (!active || !payload?.length) return null
  return (
    <div className="rounded-2xl border border-line bg-white px-3.5 py-2 text-sm shadow-lg">
      <p className="font-semibold text-muted">{label}</p>
      <p className="font-extrabold text-ink">{fmt(payload[0].value)} steps</p>
    </div>
  )
}

export function WeeklyBarChart({ data, goal, height = 240 }: { data: DayActivity[]; goal: number; height?: number }) {
  const rows = data.map((d, i) => ({ label: shortDay(d.date), steps: d.steps, today: i === data.length - 1 }))
  return (
    <div style={{ height }} role="img" aria-label="Bar chart of steps per day for the last 7 days">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={rows} margin={{ top: 8, right: 4, left: -18, bottom: 0 }}>
          <CartesianGrid vertical={false} stroke={GRID} />
          <XAxis dataKey="label" tickLine={false} axisLine={false} tick={{ fill: AXIS, fontSize: 12, fontWeight: 600 }} />
          <YAxis tickLine={false} axisLine={false} tick={{ fill: AXIS, fontSize: 12 }} tickFormatter={(v: number) => `${v / 1000}k`} />
          <Tooltip cursor={{ fill: '#EDF5E8', radius: 8 }} content={<StepTooltip />} />
          <ReferenceLine y={goal} stroke="#315C36" strokeDasharray="5 5" strokeOpacity={0.5} label={{ value: 'Goal', position: 'insideTopRight', fill: '#315C36', fontSize: 11, fontWeight: 700 }} />
          <Bar dataKey="steps" radius={[10, 10, 4, 4]} maxBarSize={44}>
            {rows.map((r, i) => (
              <Cell key={i} fill={r.today ? '#A3D65C' : '#70A83B'} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

export function TrendAreaChart({ data, goal, height = 260 }: { data: DayActivity[]; goal: number; height?: number }) {
  const rows = data.map((d) => ({ label: shortDate(d.date), steps: d.steps }))
  return (
    <div style={{ height }} role="img" aria-label="Area chart of daily steps over the selected period">
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={rows} margin={{ top: 8, right: 8, left: -18, bottom: 0 }}>
          <defs>
            <linearGradient id="areaFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#A3D65C" stopOpacity={0.55} />
              <stop offset="100%" stopColor="#A3D65C" stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid vertical={false} stroke={GRID} />
          <XAxis dataKey="label" tickLine={false} axisLine={false} interval="preserveStartEnd" minTickGap={28} tick={{ fill: AXIS, fontSize: 12 }} />
          <YAxis tickLine={false} axisLine={false} tick={{ fill: AXIS, fontSize: 12 }} tickFormatter={(v: number) => `${v / 1000}k`} />
          <Tooltip content={<StepTooltip />} />
          <ReferenceLine y={goal} stroke="#315C36" strokeDasharray="5 5" strokeOpacity={0.5} />
          <Area type="monotone" dataKey="steps" stroke="#70A83B" strokeWidth={3} fill="url(#areaFill)" />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  )
}

export function BattleBars({ participants }: { participants: BattleParticipant[] }) {
  const rows = [...participants].sort((a, b) => b.steps - a.steps).map((p) => ({ name: p.name, steps: p.steps, you: !!p.isYou }))
  return (
    <div style={{ height: Math.max(150, rows.length * 48) }} role="img" aria-label="Horizontal bar chart comparing participants' steps">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={rows} layout="vertical" margin={{ top: 0, right: 16, left: 8, bottom: 0 }}>
          <XAxis type="number" hide />
          <YAxis type="category" dataKey="name" width={92} tickLine={false} axisLine={false} tick={{ fill: '#202820', fontSize: 13, fontWeight: 600 }} />
          <Tooltip cursor={{ fill: '#EDF5E8' }} content={<StepTooltip />} />
          <Bar dataKey="steps" radius={[4, 12, 12, 4]} barSize={22}>
            {rows.map((r, i) => (
              <Cell key={i} fill={r.you ? '#70A83B' : '#C9DDB3'} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}
