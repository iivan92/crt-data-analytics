import express from 'express';
import { createTrade, createTradesBatch } from '../controllers/tradeController.js';

const router = express.Router();

router.post('/batch', createTradesBatch);
router.post('/', createTrade);

export default router;
