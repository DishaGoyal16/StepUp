import assert from 'node:assert/strict'
import { test } from 'node:test'
import { execFileSync } from 'node:child_process'
import { distance, fmt, greeting, initials, longDate, shortDate, shortDay } from '../src/lib/format.ts'

test('step totals round to whole steps with readable separators', () => {
  assert.equal(fmt(12345.6), '12,346')
  assert.equal(fmt(0), '0')
})

test('distance keeps kilometers and converts miles before rounding', () => {
  assert.equal(distance(5.25, 'km'), '5.3 km')
  assert.equal(distance(1.609344, 'mi'), '1.0 mi')
  assert.equal(distance(0, 'mi'), '0.0 mi')
})

test('greeting changes at noon and at six in the evening', () => {
  for (const [hour, expected] of [
    [0, 'Good morning!'],
    [11, 'Good morning!'],
    [12, 'Good afternoon!'],
    [17, 'Good afternoon!'],
    [18, 'Good evening!'],
    [23, 'Good evening!'],
  ]) {
    assert.equal(greeting(new Date(2026, 10, 21, hour)), expected)
  }
})

test('profile initials handle whitespace and use at most two names', () => {
  assert.equal(initials('  Disha   Goyal  '), 'DG')
  assert.equal(initials('disha'), 'D')
  assert.equal(initials('Disha Goyal Sharma'), 'DG')
  assert.equal(initials('   '), '')
})

test('calendar labels handle leap days and year boundaries', () => {
  assert.equal(shortDate('2024-02-29'), 'Feb 29')
  assert.equal(shortDay('2024-02-29'), 'Thu')
  assert.equal(shortDate('2026-12-31'), 'Dec 31')
  assert.equal(shortDay('2027-01-01'), 'Fri')
  assert.equal(longDate(new Date(2026, 10, 21, 12)), 'Saturday, November 21')
})

test('date-only activity records keep their calendar day across time zones', () => {
  const moduleUrl = new URL('../src/lib/format.ts', import.meta.url).href
  const script = `import { shortDay, shortDate } from ${JSON.stringify(moduleUrl)};
    console.log(JSON.stringify([shortDay('2027-01-01'), shortDate('2027-01-01')]))`

  for (const timeZone of ['America/Los_Angeles', 'Asia/Kolkata', 'Pacific/Auckland']) {
    const output = execFileSync(process.execPath, ['--input-type=module', '-e', script], {
      env: { ...process.env, TZ: timeZone },
      encoding: 'utf8',
    })
    assert.deepEqual(JSON.parse(output), ['Fri', 'Jan 1'], timeZone)
  }
})
