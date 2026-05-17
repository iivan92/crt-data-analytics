import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import errorHandler from './middlewares/errorHandler.js';
// Import routes here later
import tradeRoutes from './routes/tradeRoutes.js';

dotenv.config();

const app = express();
const port = process.env.PORT || 3000;

// Middlewares
app.use(cors());
app.use(express.json());

// Routes
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', message: 'API is running' });
});

app.use('/api/v1/trades', tradeRoutes);

// Error Handler Middleware
app.use(errorHandler);

app.listen(port, () => {
  console.log(`Server listening on port ${port}`);
});
