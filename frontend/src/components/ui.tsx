import { useEffect, type ButtonHTMLAttributes, type ReactNode } from 'react'
import { AlertTriangle, Inbox, X } from 'lucide-react'
import { initials } from '../lib/format'

export function cx(...parts: (string | false | null | undefined)[]) {
  return parts.filter(Boolean).join(' ')
}

/* ------------------------------ Card ------------------------------ */
export function Card({ children, className, ...rest }: { children: ReactNode; className?: string } & React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div className={cx('rounded-3xl border border-line bg-card p-5 shadow-card sm:p-6', className)} {...rest}>
      {children}
    </div>
  )
}

export function CardHeader({ title, subtitle, action }: { title: string; subtitle?: string; action?: ReactNode }) {
  return (
    <div className="mb-4 flex items-start justify-between gap-3">
      <div>
        <h2 className="text-base font-bold text-ink sm:text-lg">{title}</h2>
        {subtitle && <p className="mt-0.5 text-sm text-muted">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}

/* ----------------------------- Buttons ---------------------------- */
type BtnProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'soft' | 'ghost' | 'danger'
  size?: 'sm' | 'md'
}

export function Button({ variant = 'primary', size = 'md', className, ...rest }: BtnProps) {
  const base =
    'inline-flex items-center justify-center gap-2 rounded-full font-semibold transition active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50'
  const sizes = { sm: 'px-3.5 py-1.5 text-sm', md: 'px-5 py-2.5 text-sm' }
  const variants = {
    primary: 'bg-primary text-white shadow-sm hover:bg-dark',
    soft: 'bg-soft text-dark hover:bg-lime/30',
    ghost: 'border border-line bg-white text-ink hover:bg-soft',
    danger: 'border border-red-200 bg-white text-red-600 hover:bg-red-50',
  }
  return <button className={cx(base, sizes[size], variants[variant], className)} {...rest} />
}

/* ------------------------------ Badges ---------------------------- */
export function Pill({ children, tone = 'green' }: { children: ReactNode; tone?: 'green' | 'gray' | 'amber' }) {
  const tones = {
    green: 'bg-soft text-dark',
    gray: 'bg-[#F0F2EE] text-muted',
    amber: 'bg-[#FFF4DC] text-[#8A6100]',
  }
  return <span className={cx('inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold', tones[tone])}>{children}</span>
}

export function DemoBadge({ label = 'DEMO DATA' }: { label?: string }) {
  return (
    <span
      title="Sample values for preview only. Not from a real activity source."
      className="inline-flex items-center rounded-full border border-[#F0D9A0] bg-[#FFF8E6] px-2.5 py-0.5 text-[10px] font-extrabold tracking-wider text-[#8A6100]"
    >
      {label}
    </span>
  )
}

/* --------------------------- Progress bar ------------------------- */
export function ProgressBar({ value, className, label }: { value: number; className?: string; label?: string }) {
  const v = Math.max(0, Math.min(100, value))
  return (
    <div
      role="progressbar"
      aria-label={label}
      aria-valuenow={Math.round(v)}
      aria-valuemin={0}
      aria-valuemax={100}
      className={cx('h-2.5 w-full overflow-hidden rounded-full bg-soft', className)}
    >
      <div
        className="h-full rounded-full bg-gradient-to-r from-lime to-primary transition-[width] duration-700 ease-out"
        style={{ width: `${v}%` }}
      />
    </div>
  )
}

/* ---------------------------- Avatar ------------------------------ */
const AVATAR_COLORS = ['#70A83B', '#315C36', '#8DBF4F', '#5C8F3A', '#A3D65C', '#4A7C45']
export function Avatar({ name, size = 40, ring }: { name: string; size?: number; ring?: boolean }) {
  let h = 0
  for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0
  const bg = AVATAR_COLORS[h % AVATAR_COLORS.length]
  const dark = bg === '#A3D65C'
  return (
    <span
      aria-hidden
      className={cx('inline-flex shrink-0 select-none items-center justify-center rounded-full font-bold', ring && 'ring-2 ring-white')}
      style={{ width: size, height: size, background: bg, color: dark ? '#1f3a22' : '#fff', fontSize: size * 0.38 }}
    >
      {initials(name) || '?'}
    </span>
  )
}

/* ------------------------ Segmented control ----------------------- */
export function Segmented<T extends string>({
  value, onChange, options, label,
}: { value: T; onChange: (v: T) => void; options: { value: T; label: string }[]; label: string }) {
  return (
    <div role="tablist" aria-label={label} className="inline-flex rounded-full bg-[#EEF2EA] p-1">
      {options.map((o) => (
        <button
          key={o.value}
          role="tab"
          aria-selected={o.value === value}
          onClick={() => onChange(o.value)}
          className={cx(
            'rounded-full px-3.5 py-1.5 text-sm font-semibold transition',
            o.value === value ? 'bg-white text-dark shadow-sm' : 'text-muted hover:text-ink',
          )}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}

/* ------------------------------ Toggle ---------------------------- */
export function Toggle({ checked, onChange, label }: { checked: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <button
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
      className={cx('relative h-6 w-11 shrink-0 rounded-full transition', checked ? 'bg-primary' : 'bg-[#D5DCD0]')}
    >
      <span className={cx('absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all', checked ? 'left-[22px]' : 'left-0.5')} />
    </button>
  )
}

/* ------------------------------ Inputs ---------------------------- */
export function Field({ label, error, children }: { label: string; error?: string | null; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold text-ink">{label}</span>
      {children}
      {error && <span className="mt-1 block text-xs font-medium text-red-600">{error}</span>}
    </label>
  )
}

export const inputClass =
  'w-full rounded-2xl border border-line bg-white px-4 py-2.5 text-sm text-ink placeholder:text-[#A9B3A4] focus:border-primary focus:outline-none focus:ring-2 focus:ring-lime/40'

/* ------------------------------ Modal ----------------------------- */
export function Modal({ open, onClose, title, children }: { open: boolean; onClose: () => void; title: string; children: ReactNode }) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])
  if (!open) return null
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-ink/40 p-0 backdrop-blur-sm sm:items-center sm:p-4" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
        className="fade-up max-h-[92vh] w-full max-w-lg overflow-y-auto rounded-t-3xl bg-white p-6 shadow-2xl sm:rounded-3xl"
      >
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-bold">{title}</h2>
          <button onClick={onClose} aria-label="Close" className="rounded-full p-2 text-muted hover:bg-soft">
            <X size={18} />
          </button>
        </div>
        {children}
      </div>
    </div>
  )
}

/* -------------------------- Loading / empty ----------------------- */
export function Skeleton({ className }: { className?: string }) {
  return <div className={cx('skeleton', className)} />
}

export function EmptyState({ title, body, action }: { title: string; body: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center rounded-3xl border border-dashed border-line bg-white/60 px-6 py-12 text-center">
      <span className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-soft text-primary">
        <Inbox size={22} />
      </span>
      <h3 className="font-bold">{title}</h3>
      <p className="mt-1 max-w-sm text-sm text-muted">{body}</p>
      {action && <div className="mt-4">{action}</div>}
    </div>
  )
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="flex flex-col items-center rounded-3xl border border-red-100 bg-red-50/60 px-6 py-10 text-center">
      <AlertTriangle className="mb-2 text-red-500" />
      <p className="font-semibold text-red-700">Couldn't load this data</p>
      <p className="mt-1 text-sm text-red-600/80">{message}</p>
      {onRetry && (
        <Button variant="ghost" size="sm" className="mt-4" onClick={onRetry}>
          Try again
        </Button>
      )}
    </div>
  )
}

export function PageHeader({ title, subtitle, action, demo }: { title: string; subtitle?: string; action?: ReactNode; demo?: boolean }) {
  return (
    <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
      <div>
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-extrabold tracking-tight sm:text-3xl">{title}</h1>
          {demo && <DemoBadge />}
        </div>
        {subtitle && <p className="mt-1 text-sm text-muted sm:text-base">{subtitle}</p>}
      </div>
      {action}
    </div>
  )
}
