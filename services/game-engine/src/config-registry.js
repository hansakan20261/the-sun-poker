const { CONFIG_DEFINITIONS } = require('../../../config/config-definitions');
const { loadConfigRow, resolveRoomConfig } = require('../../../config/config-platform');

function roomField(name, bounds) {
  const definition = CONFIG_DEFINITIONS.room_defaults.fields[name];
  return Object.freeze({
    ...definition,
    type: 'integer',
    limitsConfigKey: 'room_creation_limits',
    minimumField: bounds[0],
    maximumField: bounds[1],
  });
}

const CONFIG_REGISTRY = Object.freeze({
  turn_time_sec: roomField('turn_time_sec', ['min_turn_time_sec', 'max_turn_time_sec']),
  auto_start_at: roomField('auto_start_at', ['min_players', 'max_players']),
  auto_start_delay_sec: roomField('auto_start_delay_sec', ['min_auto_start_delay_sec', 'max_auto_start_delay_sec']),
  minimum_play_minutes: roomField('minimum_play_minutes', ['min_minimum_play_minutes', 'max_minimum_play_minutes']),
});

function validateIntegerConfig(key, value, limits) {
  const definition = CONFIG_REGISTRY[key];
  const number = Number(value);
  const minimum = Number(limits?.[definition.minimumField]);
  const maximum = Number(limits?.[definition.maximumField]);
  if (!Number.isInteger(minimum) || !Number.isInteger(maximum) || minimum < 0 || maximum < minimum) {
    throw new Error(`${key} registry bounds are invalid`);
  }
  if (!Number.isInteger(number)) throw new Error(`${key} must be an integer`);
  if (number < minimum || number > maximum) {
    throw new Error(`${key} must be between ${minimum} and ${maximum}`);
  }
  return number;
}

function validateRoomTurnTimeSec(value, limits) {
  const turnTimeSec = validateIntegerConfig('turn_time_sec', value, limits);
  if (turnTimeSec <= 0) throw new Error('turn_time_sec must be a positive integer');
  return turnTimeSec;
}

function validateRoomAutoStart(autoStartAt, autoStartDelaySec, maxPlayers, limits) {
  const threshold = validateIntegerConfig('auto_start_at', autoStartAt, limits);
  const delay = validateIntegerConfig('auto_start_delay_sec', autoStartDelaySec, limits);
  if (threshold > Number(maxPlayers)) throw new Error('auto_start_at cannot exceed max_players');
  return { autoStartAt: threshold, autoStartDelaySec: delay };
}

function validateMinimumPlayMinutes(value, limits) {
  return validateIntegerConfig('minimum_play_minutes', value, limits);
}

async function loadRoomCreationLimits(pool) {
  return (await loadConfigRow(pool, 'room_creation_limits')).value;
}

async function resolveRoomTurnTimeSec(pool, value) {
  return validateRoomTurnTimeSec(value, await loadRoomCreationLimits(pool));
}

async function resolveRoomAutoStart(pool, table) {
  const snapshot = await loadRoomSnapshot(pool, table);
  return { autoStartAt: snapshot.autoStartAt, autoStartDelaySec: snapshot.autoStartDelaySec };
}

async function resolveMinimumPlayMinutes(pool, table) {
  return (await loadRoomSnapshot(pool, table)).minimumPlayMinutes;
}

async function loadRoomSnapshot(pool, table) {
  const effective = await resolveRoomConfig(pool, {
    gameTypeId: table.game_type_id,
    templateId: table.room_template_id,
    tableId: table.id,
  });
  return {
    ...effective.value,
    effective,
    texasPolicy: effective.policies.texas_holdem,
    chinesePolicy: effective.policies.chinese_poker,
    tournamentPolicy: effective.policies.tournament,
    smallBlind: Number(effective.value.small_blind),
    bigBlind: Number(effective.value.big_blind),
    ante: Number(effective.value.ante),
    minBuyIn: Number(effective.value.min_buy_in),
    maxBuyIn: Number(effective.value.max_buy_in),
    maxSeats: Number(effective.value.max_players),
    turnTimeSec: Number(effective.value.turn_time_sec),
    autoStartAt: Number(effective.value.auto_start_at),
    autoStartDelaySec: Number(effective.value.auto_start_delay_sec),
    minimumPlayMinutes: Number(effective.value.minimum_play_minutes),
    minPlayMinutes: Number(effective.value.minimum_play_minutes),
    rakePercent: Number(effective.value.rake_percent),
    rakeCap: Number(effective.value.rake_cap),
  };
}

function applyRoomSnapshotConfig(room, effective) {
  const next = {
    turnTimeSec: effective.turnTimeSec,
    autoStartAt: effective.autoStartAt,
    autoStartDelaySec: effective.autoStartDelaySec,
    minimumPlayMinutes: effective.minimumPlayMinutes,
    minPlayMinutes: effective.minimumPlayMinutes,
    rakePercent: effective.rakePercent,
    rakeCap: effective.rakeCap,
  };
  Object.assign(room.config, next);
  room.config.texasPolicy = effective.effective.policies.texas_holdem;
  room.config.chinesePolicy = effective.effective.policies.chinese_poker;
  room.config.tournamentPolicy = effective.effective.policies.tournament;
  room.texasPolicy = room.config.texasPolicy;
  room.policy = room.config.chinesePolicy;
  room.minPlayMinutes = next.minimumPlayMinutes;
  room.rakePercent = next.rakePercent;
  room.rakeCap = next.rakeCap;
  room.effectiveConfig = effective.effective;
  room.configVersion = effective.effective.revisions.room_defaults;
  room.configHash = effective.effective.hash;
  return next;
}

async function reloadRoomRuntimeConfig(pool, room, tableId) {
  return reloadRoomFromSnapshot(pool, room, tableId);
}

async function reloadRoomFromSnapshot(pool, room, tableId) {
  const result = await pool.query('SELECT * FROM game_tables WHERE id = $1', [tableId]);
  if (result.rows.length === 0) throw new Error('Table not found while reloading room config');
  return applyRoomSnapshotConfig(room, await loadRoomSnapshot(pool, result.rows[0]));
}

module.exports = {
  CONFIG_REGISTRY,
  loadRoomSnapshot,
  reloadRoomFromSnapshot,
  reloadRoomRuntimeConfig,
  resolveMinimumPlayMinutes,
  resolveRoomAutoStart,
  resolveRoomTurnTimeSec,
  validateMinimumPlayMinutes,
  validateRoomAutoStart,
  validateRoomTurnTimeSec,
};
