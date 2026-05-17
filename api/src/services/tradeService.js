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

export const createTradesBatch = async (tradesData) => {
  if (!tradesData || tradesData.length === 0) return [];

  // Generate the values placeholders, e.g., ($1, $2, ...), ($17, $18, ...)
  const valueStrings = [];
  const flatValues = [];
  
  tradesData.forEach((tradeData, index) => {
    const offset = index * 16;
    valueStrings.push(`($${offset + 1}, $${offset + 2}, $${offset + 3}, $${offset + 4}, $${offset + 5}, $${offset + 6}, $${offset + 7}, $${offset + 8}, $${offset + 9}, $${offset + 10}, $${offset + 11}, $${offset + 12}, $${offset + 13}, $${offset + 14}, $${offset + 15}, $${offset + 16})`);
    
    flatValues.push(
      tradeData.symbol,
      tradeData.timeframe,
      tradeData.direction,
      tradeData.entry_time,
      tradeData.exit_time,
      tradeData.base_high,
      tradeData.base_low,
      tradeData.trigger_extreme,
      tradeData.sweep_count,
      tradeData.has_restarted,
      tradeData.hit_50_percent,
      tradeData.result_type,
      tradeData.mae,
      tradeData.mfe,
      tradeData.htf_context,
      tradeData.metadata
    );
  });

  const sql = `
    INSERT INTO crt_trades (
      symbol, timeframe, direction, entry_time, exit_time,
      base_high, base_low, trigger_extreme, sweep_count, has_restarted,
      hit_50_percent, result_type, mae, mfe, htf_context, metadata
    ) VALUES ${valueStrings.join(', ')} RETURNING id;
  `;

  const result = await query(sql, flatValues);
  return result.rows;
};
