import { useEffect, useId, useState, type ReactNode } from 'react'

interface Props {
  value: number // 0..100
  size?: number
  stroke?: number
  children?: ReactNode
  label?: string
}

export function ProgressRing({ value, size = 260, stroke = 22, children, label }: Props) {
  const id = useId()
  const r = (size - stroke) / 2
  const c = 2 * Math.PI * r
  // animate from empty on mount
  const [shown, setShown] = useState(0)
  useEffect(() => {
    const t = requestAnimationFrame(() => setShown(Math.max(0, Math.min(100, value))))
    return () => cancelAnimationFrame(t)
  }, [value])

  return (
    <div
      role="img"
      aria-label={label ?? `${Math.round(value)} percent of daily goal`}
      className="relative mx-auto aspect-square w-full"
      style={{ maxWidth: size }}
    >
      <svg viewBox={`0 0 ${size} ${size}`} className="h-full w-full -rotate-90">
        <defs>
          <linearGradient id={id} x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#A3D65C" />
            <stop offset="100%" stopColor="#70A83B" />
          </linearGradient>
        </defs>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="#EDF5E8" strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={`url(#${id})`}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={c * (1 - shown / 100)}
          style={{ transition: 'stroke-dashoffset 1.1s cubic-bezier(.22,.8,.3,1)' }}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center text-center">{children}</div>
    </div>
  )
}
