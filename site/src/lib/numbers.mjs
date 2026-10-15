// Numbers as words, for counts set in running text ("Seventeen workflows"). The site gate reads either
// form back (check-site.mjs firstNumber), so a count stays checkable whichever way a page writes it.

import { capitalize } from './text.mjs';

const ONES = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen',
  'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen'];
const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

/**
 * 17 -> "seventeen", 27 -> "twenty-seven"; 100 and above stay numerals.
 * @param {number} n
 * @param {{ capital?: boolean }} [opts]
 */
export function numberWord(n, { capital = false } = {}) {
  let word;
  if (!Number.isInteger(n) || n < 0 || n >= 100) word = String(n);
  else if (n < 20) word = ONES[n];
  else word = TENS[Math.floor(n / 10)] + (n % 10 ? `-${ONES[n % 10]}` : '');
  return capital ? capitalize(word) : word;
}
