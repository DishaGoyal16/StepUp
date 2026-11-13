/** Injectable clock so time-dependent logic (expiry, settlement, bucket age) is testable. */
let override: (() => number) | null = null;

export function nowMs(): number {
  return override ? override() : Date.now();
}

/** Test helper: pass a function/number to freeze or advance time; pass null to restore the real clock. */
export function setClock(fn: (() => number) | number | null): void {
  override = fn === null ? null : typeof fn === 'number' ? () => fn : fn;
}
