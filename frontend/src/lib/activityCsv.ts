import type { DayActivity } from '../types'

export type ActivityCsvSource = 'demo' | 'api-unverified'

/** Quote CSV fields and prevent text cells from being interpreted as spreadsheet formulas. */
export function csvCell(value: string | number | boolean): string {
  let text = String(value)
  if (typeof value === 'string' && (/^\s*[=+\-@]/.test(text) || /^[\t\r\n]/.test(text))) {
    text = "'" + text
  }
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text
}

/** Preserve the caller's filtered order; exported counts are not verified sensor evidence. */
export function activityHistoryCsv(
  days: readonly DayActivity[],
  dailyGoal: number,
  source: ActivityCsvSource,
): string {
  if (!Number.isFinite(dailyGoal) || dailyGoal <= 0) throw new RangeError('Daily goal must be positive')
  const header = 'date,steps,distance_km,calories,active_minutes,daily_goal,goal_met,data_source'
  const lines = days.map((day) => {
    const values = [day.steps, day.distanceKm, day.calories, day.activeMinutes]
    if (values.some((value) => !Number.isFinite(value) || value < 0)) {
      throw new RangeError('Activity values must be finite and non-negative')
    }
    return [day.date, ...values, dailyGoal, day.steps >= dailyGoal, source].map(csvCell).join(',')
  })
  return [header, ...lines].join('\r\n') + '\r\n'
}

export function downloadActivityCsv(csv: string): void {
  const url = URL.createObjectURL(new Blob(['\uFEFF', csv], { type: 'text/csv;charset=utf-8' }))
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = 'stepup-activity-history.csv'
  try {
    document.body.appendChild(anchor)
    anchor.click()
  } finally {
    anchor.remove()
    // Give the browser time to start reading the blob before releasing it.
    setTimeout(() => URL.revokeObjectURL(url), 30_000)
  }
}
