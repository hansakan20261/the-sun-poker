const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');

const BCRYPT_PREFIX = /^\$2[aby]\$/;

function sanitizeTable(table) {
  if (!table) return table;
  const { password, ...safeTable } = table;
  return { ...safeTable, has_password: Boolean(password) };
}

function isHashedPassword(value) {
  return BCRYPT_PREFIX.test(value || '');
}

async function hashRoomPassword(password, rounds) {
  if (!password) return null;
  return bcrypt.hash(password, rounds);
}

async function verifyRoomPassword(password, storedPassword) {
  if (!storedPassword) return true;
  if (!password) return false;
  return isHashedPassword(storedPassword)
    ? bcrypt.compare(password, storedPassword)
    : password === storedPassword;
}

function issueRoomAccessToken(tableId, userId, expiresInMinutes) {
  if (!Number.isInteger(expiresInMinutes) || expiresInMinutes <= 0) {
    throw new Error('Room access token TTL must be a positive integer');
  }
  return jwt.sign(
    { purpose: 'room_access', tableId, userId },
    process.env.JWT_SECRET,
    { expiresIn: `${expiresInMinutes}m` },
  );
}

module.exports = {
  hashRoomPassword,
  isHashedPassword,
  issueRoomAccessToken,
  sanitizeTable,
  verifyRoomPassword,
};
