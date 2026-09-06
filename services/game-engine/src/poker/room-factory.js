const { GameRoom } = require('./game-room');
const { ChinesePokerRoom } = require('./chinese-poker');

function applyTableMetadata(room, tableRow, roomConfig) {
  room.configVersion = tableRow.config_version;
  room.configHash = tableRow.config_hash;
  room.effectiveConfig = roomConfig.effective;
  room.isPractice = tableRow.is_practice === true;
  room.isPrivate = tableRow.is_private === true || Boolean(tableRow.password);
  return room;
}

function createRoomFromSnapshot(tableRow, roomConfig) {
  const slug = tableRow.game_type_slug || 'texas_holdem';
  const room = slug === 'chinese_poker'
    ? new ChinesePokerRoom(tableRow.id, roomConfig)
    : new GameRoom(tableRow.id, roomConfig);
  return applyTableMetadata(room, tableRow, roomConfig);
}

function createTexasRoom(tableRow, roomConfig) {
  return applyTableMetadata(new GameRoom(tableRow.id, roomConfig), tableRow, roomConfig);
}

function createChineseRoom(tableRow, roomConfig) {
  return applyTableMetadata(new ChinesePokerRoom(tableRow.id, roomConfig), tableRow, roomConfig);
}

module.exports = {
  applyTableMetadata,
  createChineseRoom,
  createRoomFromSnapshot,
  createTexasRoom,
};
