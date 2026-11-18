import { useId } from 'react'

export function Logo({ size = 36, text = true }: { size?: number; text?: boolean }) {
  // Unique gradient id per instance: a gradient defined inside a display:none SVG (e.g. the
  // hidden desktop sidebar) is not resolvable from another SVG, which left the logo blank.
  const gid = useId()
  return (
    <span className="inline-flex items-center gap-2.5">
      <svg width={size} height={size} viewBox="0 0 64 64" aria-hidden>
        <defs>
          <linearGradient id={gid} x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#A3D65C" />
            <stop offset="1" stopColor="#70A83B" />
          </linearGradient>
        </defs>
        <rect width="64" height="64" rx="18" fill={`url(#${gid})`} />
        <path d="M16 43h12V31h12V19h8" fill="none" stroke="#fff" strokeWidth="6" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
      {text && (
        <span className="text-xl font-extrabold tracking-tight text-dark">
          Step<span className="text-primary">Up</span>
        </span>
      )}
    </span>
  )
}
