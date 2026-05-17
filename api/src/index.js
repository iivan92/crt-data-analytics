import express from 'express';
import cors from 'cors';
import { errorHandler } from './middlewares/errorHandler.js';

const app = express();
const PORT = process.env.PORT || 3000;

// Configuración de middlewares base
app.use(cors());
app.use(express.json());

// Rutas de la API (ejemplo)
app.get('/api/health', (req, res) => {
  res.status(200).json({ status: 'OK', message: 'CRT Quant API is running' });
});

// Middleware centralizado de manejo de errores (debe ir al final)
app.use(errorHandler);

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
});
