import { query } from '../db/index.js';

export const createTrade = async (tradeData) => {
  const {
    symbol,
    timeframe,
    direction,
    entry_time,
    exit_time,
    base_high,
    base_low,
    trigger_extreme,
    sweep_count,
    has_restarted,
    hit_50_percent,
    result_type,
    mae,
    mfe,
    htf_context,
    metadata,
  } = tradeData;

  const sql = `
    INSERT INTO crt_trades (
      symbol, timeframe, direction, entry_time, exit_time,
      base_high, base_low, trigger_extreme, sweep_count, has_restarted,
      hit_50_percent, result_type, mae, mfe, htf_context, metadata
    ) VALUES (
      $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
      $11, $12, $13, $14, $15, $16
    ) RETURNING *;
  `;

  const values = [
    symbol,
    timeframe,
    direction,
    entry_time,
    exit_time,
    base_high,
    base_low,
    trigger_extreme,
    sweep_count,
    has_restarted,
    hit_50_percent,
    result_type,
    mae,
    mfe,
    htf_context,
    metadata,
  ];

  const result = await query(sql, values);
  return result.rows[0];
};
