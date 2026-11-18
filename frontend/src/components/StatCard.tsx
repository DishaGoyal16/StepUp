import type { LucideIcon } from 'lucide-react'

export function StatCard({
  icon: Icon, label, value, note,
}: { icon: LucideIcon; label: string; value: string; note?: string }) {
  return (
    <div className="rounded-2xl border border-line bg-white p-4 transition hover:shadow-card">
      <span className="mb-3 flex h-10 w-10 items-center justify-center rounded-xl bg-soft text-primary">
        <Icon size={20} />
      </span>
      <p className="text-2xl font-extrabold leading-none tracking-tight">{value}</p>
      <p className="mt-1.5 text-sm font-semibold text-ink">{label}</p>
      {note && <p className="text-xs text-muted">{note}</p>}
    </div>
  )
}
