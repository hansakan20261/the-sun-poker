function getRoomTurnTimeSec(room) {
  const turnTimeSec = Number(room.config?.turnTimeSec);
  if (!Number.isInteger(turnTimeSec) || turnTimeSec <= 0) {
    throw new Error('room.config.turnTimeSec must be a positive integer');
  }
  return turnTimeSec;
}

function clearRoomTurnTimer(room, clearTimer = clearTimeout) {
  if (room._turnTimer !== null && room._turnTimer !== undefined) clearTimer(room._turnTimer);
  room._turnTimer = null;
  room._turnTotalSeconds = null;
  room._turnStartedAt = null;
  room._turnDeadlineAt = null;
}

function scheduleRoomTurnTimer(room, onTimeout, options = {}) {
  const setTimer = options.setTimer || setTimeout;
  const clearTimer = options.clearTimer || clearTimeout;
  const now = options.now || Date.now;
  clearRoomTurnTimer(room, clearTimer);
  const turnTimeSec = getRoomTurnTimeSec(room);
  const startedAt = now();
  room._turnTotalSeconds = turnTimeSec;
  room._turnStartedAt = startedAt;
  room._turnDeadlineAt = startedAt + turnTimeSec * 1000;
  room._turnTimer = setTimer(() => {
    room._turnTimer = null;
    room._turnTotalSeconds = null;
    room._turnStartedAt = null;
    room._turnDeadlineAt = null;
    onTimeout();
  }, turnTimeSec * 1000);
  return room._turnTimer;
}

module.exports = { clearRoomTurnTimer, getRoomTurnTimeSec, scheduleRoomTurnTimer };
