import express from 'express';
import { createTrade, createTradesBatch, getTradesStats, clearTrades } from '../controllers/tradeController.js';

const router = express.Router();

router.get('/stats', getTradesStats);
router.post('/batch', createTradesBatch);
router.post('/', createTrade);
router.delete('/', clearTrades);

export default router;
