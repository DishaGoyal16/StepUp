import assert from 'node:assert/strict'
import { test } from 'node:test'
import { activityHistoryCsv, csvCell, downloadActivityCsv } from '../src/lib/activityCsv.ts'

const day = { date: '2026-11-27', steps: 8500, distanceKm: 5.2, calories: 320, activeMinutes: 42 }

test('exports explicit units, source and goal status with CRLF records', () => {
  assert.equal(activityHistoryCsv([day], 8000, 'demo'),
    'date,steps,distance_km,calories,active_minutes,daily_goal,goal_met,data_source\r\n' +
    '2026-11-27,8500,5.2,320,42,8000,true,demo\r\n')
})

test('empty history exports headers without inventing data', () => {
  assert.equal(activityHistoryCsv([], 8000, 'demo').split('\r\n').filter(Boolean).length, 1)
})

test('preserves filtered row order and does not mutate the supplied records', () => {
  const days = Object.freeze([Object.freeze(day), Object.freeze({ ...day, date: '2026-11-26', steps: 0 })])
  const rows = activityHistoryCsv(days, 8500, 'api-unverified').trimEnd().split('\r\n')
  assert.equal(rows.length, 3)
  assert.match(rows[1], /^2026-11-27,.*true,api-unverified$/)
  assert.match(rows[2], /^2026-11-26,0,.*false,api-unverified$/)
  assert.equal(days[0].date, '2026-11-27')
})

test('quotes delimiters, quotes and newlines correctly', () => {
  assert.equal(csvCell('a,b'), '"a,b"')
  assert.equal(csvCell('say "hello"'), '"say ""hello"""')
  assert.equal(csvCell('line one\nline two'), '"line one\nline two"')
})

test('escapes formula-like text while retaining ordinary numeric values', () => {
  for (const text of ['=1+1', '+SUM(A1)', '-1+1', '@SUM(A1)', '  =1', '\tvalue']) {
    assert.ok(csvCell(text).startsWith("'"), text)
  }
  assert.equal(csvCell(42), '42')
  assert.equal(csvCell(false), 'false')
})

test('rejects invalid daily goals and invalid measurements', () => {
  for (const goal of [0, -1, NaN, Infinity]) assert.throws(() => activityHistoryCsv([day], goal, 'demo'), RangeError)
  for (const key of ['steps', 'distanceKm', 'calories', 'activeMinutes']) {
    for (const value of [-1, NaN, Infinity]) {
      assert.throws(() => activityHistoryCsv([{ ...day, [key]: value }], 8000, 'demo'), RangeError)
    }
  }
})

test('download creates a CSV blob, clicks a temporary link and releases the URL', async (t) => {
  let clicked = false
  let removed = false
  let appended = false
  let blob
  let cleanup
  let revoked
  const anchor = { href: '', download: '', click: () => { clicked = true }, remove: () => { removed = true } }
  t.mock.method(URL, 'createObjectURL', (value) => { blob = value; return 'blob:test-export' })
  t.mock.method(URL, 'revokeObjectURL', (value) => { revoked = value })
  t.mock.method(globalThis, 'setTimeout', (callback) => { cleanup = callback; return 1 })
  const prior = Object.getOwnPropertyDescriptor(globalThis, 'document')
  Object.defineProperty(globalThis, 'document', { configurable: true, value: {
    createElement: (tag) => { assert.equal(tag, 'a'); return anchor },
    body: { appendChild: (value) => { assert.equal(value, anchor); appended = true } },
  } })
  t.after(() => { if (prior) Object.defineProperty(globalThis, 'document', prior); else delete globalThis.document })
  downloadActivityCsv('date,steps\r\n2026-11-27,8500\r\n')
  assert.ok(appended && clicked && removed)
  assert.equal(anchor.download, 'stepup-activity-history.csv')
  assert.equal(anchor.href, 'blob:test-export')
  assert.equal(blob.type, 'text/csv;charset=utf-8')
  assert.match(await blob.text(), /2026-11-27,8500/)
  assert.equal(revoked, undefined)
  cleanup()
  assert.equal(revoked, 'blob:test-export')
})
