const crypto = require('crypto');

async function deductBuyIn(pool, { userId, tableId, amount }) {
  const client = await pool.connect();
  const sessionId = crypto.randomUUID();
  try {
    await client.query('BEGIN');
    const wallet = await client.query(
      'SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE',
      [userId],
    );
    if (wallet.rows.length === 0) throw new Error('Wallet not found');
    if (Number(wallet.rows[0].balance) < amount) throw new Error('Insufficient balance');
    const updated = await client.query(
      'UPDATE wallets SET balance = balance - $1, updated_at = NOW() WHERE user_id = $2 RETURNING balance',
      [amount, userId],
    );
    await client.query(
      `INSERT INTO game_wallet_sessions (id, table_id, user_id, buy_in)
       VALUES ($1, $2, $3, $4)`,
      [sessionId, tableId, userId, amount],
    );
    await client.query(
      `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id)
       VALUES ($1, 'game_buy_in', $2, $3, $4)`,
      [userId, -amount, updated.rows[0].balance, tableId],
    );
    await client.query('COMMIT');
    return { sessionId, balance: Number(updated.rows[0].balance) };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function addToBuyIn(pool, { sessionId, userId, tableId, amount }) {
  if (!sessionId) return deductBuyIn(pool, { userId, tableId, amount });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const session = await client.query(
      `UPDATE game_wallet_sessions
       SET buy_in = buy_in + $1
       WHERE id = $2 AND user_id = $3 AND table_id = $4 AND status = 'active'
       RETURNING id`,
      [amount, sessionId, userId, tableId],
    );
    if (session.rows.length === 0) throw new Error('Active game wallet session not found');
    const wallet = await client.query(
      'SELECT balance FROM wallets WHERE user_id = $1 FOR UPDATE',
      [userId],
    );
    if (wallet.rows.length === 0) throw new Error('Wallet not found');
    if (Number(wallet.rows[0].balance) < amount) throw new Error('Insufficient balance');
    const updated = await client.query(
      'UPDATE wallets SET balance = balance - $1, updated_at = NOW() WHERE user_id = $2 RETURNING balance',
      [amount, userId],
    );
    await client.query(
      `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id)
       VALUES ($1, 'game_buy_in', $2, $3, $4)`,
      [userId, -amount, updated.rows[0].balance, tableId],
    );
    await client.query('COMMIT');
    return { sessionId, balance: Number(updated.rows[0].balance) };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function cashOut(pool, { sessionId, userId, tableId, amount }) {
  if (!sessionId) return false;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const session = await client.query(
      `UPDATE game_wallet_sessions
       SET status = 'cashed_out', cash_out = $1, cashed_out_at = NOW()
       WHERE id = $2 AND user_id = $3 AND table_id = $4 AND status = 'active'
       RETURNING id`,
      [amount, sessionId, userId, tableId],
    );
    if (session.rows.length === 0) {
      await client.query('ROLLBACK');
      return false;
    }
    const updated = await client.query(
      'UPDATE wallets SET balance = balance + $1, updated_at = NOW() WHERE user_id = $2 RETURNING balance',
      [amount, userId],
    );
    if (updated.rows.length === 0) throw new Error('Wallet not found');
    await client.query(
      `INSERT INTO transactions (user_id, type, amount, balance_after, reference_id)
       VALUES ($1, 'game_cashout', $2, $3, $4)`,
      [userId, amount, updated.rows[0].balance, tableId],
    );
    await client.query('COMMIT');
    return true;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

module.exports = { cashOut, deductBuyIn };
