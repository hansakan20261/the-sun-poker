// Cryptographically secure deck
const crypto = require('crypto');

const SUITS = ['h', 'd', 'c', 's']; // hearts, diamonds, clubs, spades
const RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'];

function createDeck() {
  const deck = [];
  for (const s of SUITS) for (const r of RANKS) deck.push(r + s);
  return deck;
}

function shuffle(deck) {
  const arr = [...deck];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = crypto.randomInt(0, i + 1);
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

function newShuffledDeck() { return shuffle(createDeck()); }

module.exports = { createDeck, shuffle, newShuffledDeck, SUITS, RANKS };
