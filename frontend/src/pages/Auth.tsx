import { useState, type FormEvent, type ReactNode } from 'react'
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom'
import { Eye, EyeOff, Flame, Loader2, Trophy, Users } from 'lucide-react'
import { Logo } from '../components/Logo'
import { ProgressRing } from '../components/ProgressRing'
import { Button, DemoBadge, Field, inputClass } from '../components/ui'
import { DEMO_ACCOUNT } from '../data/demo'
import { useApp } from '../hooks/useApp'

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

function AuthShell({ title, subtitle, children, footer }: { title: string; subtitle: string; children: ReactNode; footer: ReactNode }) {
  return (
    <div className="grid min-h-screen lg:grid-cols-2">
      <div className="relative hidden flex-col justify-between overflow-hidden bg-gradient-to-br from-soft via-white to-[#F3F9E9] p-12 lg:flex">
        <Logo />
        <div>
          <div className="mx-auto w-64">
            <ProgressRing value={78} size={256} stroke={22}>
              <span className="text-4xl font-extrabold text-ink">7,842</span>
              <span className="text-sm font-semibold text-muted">of 10,000 steps</span>
            </ProgressRing>
          </div>
          <div className="mx-auto mt-3 flex justify-center">
            <DemoBadge />
          </div>
          <h2 className="mx-auto mt-8 max-w-sm text-center text-3xl font-extrabold leading-tight text-dark">
            Small steps. Big streaks. Better days.
          </h2>
          <ul className="mx-auto mt-6 flex max-w-sm justify-center gap-6 text-sm font-semibold text-dark/80">
            <li className="flex items-center gap-1.5"><Flame size={16} className="text-primary" /> Streaks</li>
            <li className="flex items-center gap-1.5"><Trophy size={16} className="text-primary" /> Challenges</li>
            <li className="flex items-center gap-1.5"><Users size={16} className="text-primary" /> Buddies</li>
          </ul>
        </div>
        <p className="text-xs text-muted">Demo build — all activity data is sample data.</p>
      </div>

      <div className="flex items-center justify-center px-5 py-10 sm:px-10">
        <div className="fade-up w-full max-w-md">
          <div className="mb-8 lg:hidden">
            <Logo />
          </div>
          <h1 className="text-3xl font-extrabold tracking-tight">{title}</h1>
          <p className="mt-1.5 text-muted">{subtitle}</p>
          <div className="mt-7">{children}</div>
          <p className="mt-6 text-center text-sm text-muted">{footer}</p>
        </div>
      </div>
    </div>
  )
}

function PasswordInput({ value, onChange, autoComplete }: { value: string; onChange: (v: string) => void; autoComplete: string }) {
  const [show, setShow] = useState(false)
  return (
    <div className="relative">
      <input
        type={show ? 'text' : 'password'}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        autoComplete={autoComplete}
        className={`${inputClass} pr-11`}
        placeholder="At least 8 characters"
      />
      <button
        type="button"
        onClick={() => setShow((s) => !s)}
        aria-label={show ? 'Hide password' : 'Show password'}
        className="absolute right-3 top-1/2 -translate-y-1/2 text-muted hover:text-ink"
      >
        {show ? <EyeOff size={18} /> : <Eye size={18} />}
      </button>
    </div>
  )
}

export function LoginPage() {
  const { user, login } = useApp()
  const navigate = useNavigate()
  const location = useLocation()
  const from = (location.state as { from?: string } | null)?.from ?? '/'
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (user) return <Navigate to={from} replace />

  async function submit(e?: FormEvent, creds?: { email: string; password: string }) {
    e?.preventDefault()
    const em = creds?.email ?? email
    const pw = creds?.password ?? password
    if (!EMAIL_RE.test(em.trim())) return setError('Enter a valid email address.')
    if (!pw) return setError('Enter your password.')
    setBusy(true)
    setError(null)
    try {
      await login(em, pw)
      navigate(from, { replace: true })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not sign in.')
      setBusy(false)
    }
  }

  return (
    <AuthShell
      title="Welcome back"
      subtitle="Log in to see today's steps."
      footer={<>New to StepUp? <Link to="/register" className="font-semibold text-primary hover:text-dark">Create an account</Link></>}
    >
      <form onSubmit={submit} className="space-y-4" noValidate>
        <Field label="Email">
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" className={inputClass} placeholder="you@example.com" />
        </Field>
        <Field label="Password">
          <PasswordInput value={password} onChange={setPassword} autoComplete="current-password" />
        </Field>
        {error && <p role="alert" className="rounded-2xl bg-red-50 px-4 py-2.5 text-sm font-medium text-red-700">{error}</p>}
        <Button type="submit" disabled={busy} className="w-full">
          {busy && <Loader2 size={16} className="animate-spin" />} Log in
        </Button>
      </form>

      <div className="mt-6 rounded-3xl border border-line bg-white p-4">
        <div className="flex items-center justify-between gap-2">
          <p className="text-sm font-bold">Try the demo account</p>
          <DemoBadge label="DEMO" />
        </div>
        <p className="mt-1 text-sm text-muted">
          <span className="font-semibold text-ink">{DEMO_ACCOUNT.email}</span> · <span className="font-semibold text-ink">{DEMO_ACCOUNT.password}</span>
        </p>
        <Button
          variant="soft"
          size="sm"
          className="mt-3"
          disabled={busy}
          onClick={() => {
            setEmail(DEMO_ACCOUNT.email)
            setPassword(DEMO_ACCOUNT.password)
            void submit(undefined, DEMO_ACCOUNT)
          }}
        >
          Sign in as demo user
        </Button>
      </div>
    </AuthShell>
  )
}

export function RegisterPage() {
  const { user, register } = useApp()
  const navigate = useNavigate()
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [errors, setErrors] = useState<{ name?: string; email?: string; password?: string; form?: string }>({})

  if (user) return <Navigate to="/" replace />

  async function submit(e: FormEvent) {
    e.preventDefault()
    const next: typeof errors = {}
    if (name.trim().length < 2) next.name = 'Enter your name.'
    if (!EMAIL_RE.test(email.trim())) next.email = 'Enter a valid email address.'
    if (password.length < 8) next.password = 'Use at least 8 characters.'
    setErrors(next)
    if (Object.keys(next).length) return
    setBusy(true)
    try {
      await register(name, email, password)
      navigate('/', { replace: true })
    } catch (err) {
      setErrors({ form: err instanceof Error ? err.message : 'Could not create account.' })
      setBusy(false)
    }
  }

  return (
    <AuthShell
      title="Create your account"
      subtitle="Set a goal, start stepping."
      footer={<>Already have an account? <Link to="/login" className="font-semibold text-primary hover:text-dark">Log in</Link></>}
    >
      <form onSubmit={submit} className="space-y-4" noValidate>
        <Field label="Full name" error={errors.name}>
          <input value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" className={inputClass} placeholder="Alex Rivera" />
        </Field>
        <Field label="Email" error={errors.email}>
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" className={inputClass} placeholder="you@example.com" />
        </Field>
        <Field label="Password" error={errors.password}>
          <PasswordInput value={password} onChange={setPassword} autoComplete="new-password" />
        </Field>
        {errors.form && <p role="alert" className="rounded-2xl bg-red-50 px-4 py-2.5 text-sm font-medium text-red-700">{errors.form}</p>}
        <Button type="submit" disabled={busy} className="w-full">
          {busy && <Loader2 size={16} className="animate-spin" />} Create account
        </Button>
        <p className="text-xs text-muted">
          Demo build: accounts are stored only in this browser. Activity numbers are sample data until a real source is connected.
        </p>
      </form>
    </AuthShell>
  )
}
