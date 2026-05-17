import { tradeSchema } from '../schemas/tradeSchema.js';
import * as tradeService from '../services/tradeService.js';

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
