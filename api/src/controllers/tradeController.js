import { tradeSchema } from '../schemas/tradeSchema.js';
import * as tradeService from '../services/tradeService.js';
import { z } from 'zod';

export const createTrade = async (req, res, next) => {
  try {
    const parsedData = tradeSchema.parse(req.body);
    const newTrade = await tradeService.createTrade(parsedData);
    
    res.status(201).json({
      status: 'success',
      data: { trade: newTrade },
    });
  } catch (error) {
    if (error.name === 'ZodError') {
      return res.status(400).json({
        status: 'error',
        message: 'Validation Error',
        errors: error.errors,
      });
    }
    next(error);
  }
};

export const createTradesBatch = async (req, res, next) => {
  try {
    const batchSchema = z.array(tradeSchema);
    const parsedData = batchSchema.parse(req.body);
    
    const insertedIds = await tradeService.createTradesBatch(parsedData);
    
    res.status(201).json({
      status: 'success',
      message: `${insertedIds.length} trades inserted successfully`,
      data: { inserted_count: insertedIds.length },
    });
  } catch (error) {
    if (error.name === 'ZodError') {
      return res.status(400).json({
        status: 'error',
        message: 'Validation Error',
        errors: error.errors,
      });
    }
    next(error);
  }
};

export const getTradesStats = async (req, res, next) => {
  try {
    const stats = await tradeService.getTradesStats();
    res.status(200).json({
      status: 'success',
      data: stats,
    });
  } catch (error) {
    next(error);
  }
};
