import assert from 'node:assert/strict';

function getRunMargin(winnerRuns, otherRuns) {
  return Math.max(winnerRuns - otherRuns, 0);
}

function getWicketMargin(lineupSize, dismissedWickets) {
  return Math.max(lineupSize - dismissedWickets, 0);
}

function formatMargin(amount, type) {
  return `won by ${amount} ${type}${amount === 1 ? '' : 's'}`;
}

assert.equal(getRunMargin(42, 35), 7, 'run margins should remain unchanged');
assert.equal(getWicketMargin(6, 2), 4, 'six-player lineup with two dismissals should win by four wickets');
assert.equal(formatMargin(getWicketMargin(2, 1), 'wicket'), 'won by 1 wicket', 'singular wicket wording should be preserved');

console.log('Win margin coverage passed.');
