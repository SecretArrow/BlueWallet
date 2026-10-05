import { ERROR_CODES } from './protocol.mjs';
import { OctraWalletError } from './errors.mjs';

/** Micro-OCT per OCT (6 decimals, exact). */
export const MICRO_PER_OCT = 1_000_000n;

/** Octra address shape: "oct" + 44 base58 chars (47 total).
 * Base58 excludes 0, O, I, l — hence A-H (no I), P + Q-Z (no O), a-k/m-z. */
const ADDRESS_RE = /^oct[1-9A-HJ-NPQ-Za-km-z]{44}$/;

/** True for well-formed Octra addresses (shape only, no chain lookup). */
export function isValidAddress(addr) {
  return typeof addr === 'string' && ADDRESS_RE.test(addr.trim());
}

/**
 * Convert an OCT amount to exact micro-OCT string.
 *
 * Accepts string ("10.5") or number. A value that cannot be written in
 * exactly 6 decimals (e.g. 0.1 + 0.2 = 0.30000000000000004) throws
 * INVALID_AMOUNT — pass a string for exact control. Rejects negatives,
 * empty input and non-numeric strings.
 */
export function octToMicro(input) {
  const s = typeof input === 'number' ? String(input) : input;
  if (typeof s !== 'string' || s.trim() === '') {
    throw new OctraWalletError(ERROR_CODES.INVALID_AMOUNT, `Invalid amount: ${String(input)}`);
  }
  const t = s.trim();
  const m = /^(\d+)(?:\.(\d+))?$/.exec(t);
  if (!m) {
    throw new OctraWalletError(ERROR_CODES.INVALID_AMOUNT, `Invalid amount: "${t}"`);
  }
  const frac = (m[2] ?? '').padEnd(6, '0');
  if (frac.length > 6) {
    throw new OctraWalletError(
      ERROR_CODES.INVALID_AMOUNT,
      `Amount exceeds 6 decimals, pass fewer decimals or a raw value: "${t}"`,
    );
  }
  return (BigInt(m[1]) * MICRO_PER_OCT + BigInt(frac)).toString();
}

/** Convert micro-OCT (string|number|bigint) to an exact OCT decimal string. */
export function fromMicroOCT(raw) {
  let v;
  try {
    v = BigInt(typeof raw === 'bigint' ? raw : String(raw).trim());
  } catch {
    throw new OctraWalletError(ERROR_CODES.INVALID_AMOUNT, `Invalid raw amount: ${String(raw)}`);
  }
  if (v < 0n) {
    throw new OctraWalletError(ERROR_CODES.INVALID_AMOUNT, `Negative raw amount: ${String(raw)}`);
  }
  const whole = v / MICRO_PER_OCT;
  const frac = (v % MICRO_PER_OCT).toString().padStart(6, '0').replace(/0+$/, '');
  return frac === '' ? whole.toString() : `${whole}.${frac}`;
}

/**
 * Resolve exactly one of amount/amountOct into a micro-OCT string.
 * Passing both (or neither) throws INVALID_AMOUNT.
 */
export function resolveAmount({ amount, amountOct }, field = 'amount') {
  const hasRaw = amount !== undefined && amount !== null;
  const hasOct = amountOct !== undefined && amountOct !== null;
  if (hasRaw && hasOct) {
    throw new OctraWalletError(
      ERROR_CODES.INVALID_AMOUNT,
      `Pass either ${field} or ${field}Oct, never both`,
    );
  }
  if (hasRaw) {
    const s = String(amount).trim();
    if (!/^\d+$/.test(s)) {
      throw new OctraWalletError(ERROR_CODES.INVALID_AMOUNT, `Invalid ${field}: "${amount}"`);
    }
    return s.replace(/^0+(?=\d)/, '');
  }
  if (hasOct) return octToMicro(amountOct);
  throw new OctraWalletError(ERROR_CODES.INVALID_AMOUNT, `Missing ${field} or ${field}Oct`);
}
