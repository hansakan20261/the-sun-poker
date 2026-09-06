const jwt = require('jsonwebtoken');

function verifyRoomAccessToken(token, tableId, userId) {
  if (!token) return false;
  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    return payload.purpose === 'room_access'
      && payload.tableId === tableId
      && payload.userId === userId;
  } catch {
    return false;
  }
}

function isAdminRole(role) {
  return role === 'admin' || role === 'super_admin';
}

function canAccessRoom(room, socket, accessToken) {
  if (!room.isPrivate) return true;
  if ([...room.players.values()].some((player) => player.id === socket.user.id)) return true;
  return verifyRoomAccessToken(accessToken, room.tableId, socket.user.id);
}

module.exports = { canAccessRoom, isAdminRole, verifyRoomAccessToken };
