function clearRoomAutoStart(room, clearTimer = clearTimeout) {
  if (room._autoStartTimer !== null && room._autoStartTimer !== undefined) clearTimer(room._autoStartTimer);
  room._autoStartTimer = null;
  room._autoStartStartedAt = null;
  room._autoStartDeadlineAt = null;
}

function scheduleRoomAutoStart(room, onStart, options = {}) {
  const setTimer = options.setTimer || setTimeout;
  const clearTimer = options.clearTimer || clearTimeout;
  const now = options.now || Date.now;
  const threshold = Number(room.config?.autoStartAt);
  const delaySec = Number(room.config?.autoStartDelaySec);
  if (!Number.isInteger(threshold) || threshold <= 0) throw new Error('room.config.autoStartAt must be a positive integer');
  if (!Number.isInteger(delaySec) || delaySec < 0) throw new Error('room.config.autoStartDelaySec must be a non-negative integer');
  const isPlaying = room.isPlaying === true || (room.phase !== undefined && room.phase !== 'waiting' && room.phase !== 'result');
  if (isPlaying || room.players.size < threshold) {
    clearRoomAutoStart(room, clearTimer);
    return false;
  }
  if (room._autoStartTimer !== null && room._autoStartTimer !== undefined) return false;
  const startedAt = now();
  room._autoStartStartedAt = startedAt;
  room._autoStartDeadlineAt = startedAt + delaySec * 1000;
  room._autoStartTimer = setTimer(() => {
    room._autoStartTimer = null;
    room._autoStartStartedAt = null;
    room._autoStartDeadlineAt = null;
    const canStart = room.isPlaying !== true && (room.phase === undefined || room.phase === 'waiting') && room.players.size >= threshold;
    if (canStart) onStart();
  }, delaySec * 1000);
  return true;
}

module.exports = { clearRoomAutoStart, scheduleRoomAutoStart };
