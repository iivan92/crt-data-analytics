import pg from 'pg';
import dotenv from 'dotenv';

dotenv.config();

const { Pool } = pg;

const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'postgres_db',
  database: process.env.DB_NAME || 'crt_quant',
  password: process.env.DB_PASSWORD || 'admin',
  port: process.env.DB_PORT || 5432,
});

pool.on('error', (err, client) => {
  console.error('Unexpected error on idle client', err);
  process.exit(-1);
});

export const query = (text, params) => pool.query(text, params);
export default pool;
