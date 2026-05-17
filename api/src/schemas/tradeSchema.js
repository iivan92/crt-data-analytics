import { z } from 'zod';

export const tradeSchema = z.object({
  symbol: z.string().min(1).max(10),
  timeframe: z.string().min(1).max(5),
  direction: z.enum(['BULL', 'BEAR', 'BUY', 'SELL']),
  
  // Tiempos (permitir ISO string o timestamps y luego convertirlos)
  entry_time: z.string().datetime(),
  exit_time: z.string().datetime().optional(),
  
  // Anatomía del Rango Local
  base_high: z.number(),
  base_low: z.number(),
  trigger_extreme: z.number(),
  
  // Métricas del Setup Local
  sweep_count: z.number().int().min(1).default(1),
  has_restarted: z.boolean().default(false),
  hit_50_percent: z.boolean().default(false),
  
  // Resultado y Excursión
  result_type: z.enum(['TP_EXPANSION', 'TP_REINICIO', 'SL', 'DESCARTADO']),
  mae: z.number().optional(),
  mfe: z.number().optional(),
  
  // JSONs
  htf_context: z.record(z.any()).optional().default({}),
  metadata: z.record(z.any()).optional().default({}),
});
