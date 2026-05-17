-- Esquema de la Base de Datos para el Sistema CRT Quant
CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE crt_trades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    symbol VARCHAR(10) NOT NULL,            
    timeframe VARCHAR(5) NOT NULL,          
    direction VARCHAR(10) NOT NULL,         
    
    -- Tiempos 
    entry_time TIMESTAMPTZ NOT NULL,        
    exit_time TIMESTAMPTZ,                  
    
    -- Anatomía del Rango Local
    base_high NUMERIC NOT NULL,
    base_low NUMERIC NOT NULL,
    trigger_extreme NUMERIC NOT NULL,       
    
    -- Métricas del Setup Local
    sweep_count INT DEFAULT 1,              
    has_restarted BOOLEAN DEFAULT FALSE,    
    hit_50_percent BOOLEAN DEFAULT FALSE,   
    
    -- Resultado y Excursión
    result_type VARCHAR(20) NOT NULL,       
    mae NUMERIC,                            
    mfe NUMERIC,                            
    
    -- ********** ESCALABILIDAD FUTURA ********** --
    -- Aquí guardaremos el sesgo de temporalidades mayores en el futuro
    -- Ej: {"D1_bias": "BULL", "H4_state": "RESTARTED_BEAR"}
    htf_context JSONB DEFAULT '{}'::jsonb,  
    
    -- Para guardar parámetros de optimización o notas sin alterar la tabla
    -- Ej: {"bot_version": "v2.1", "session": "London"}
    metadata JSONB DEFAULT '{}'::jsonb,     
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

SELECT create_hypertable('crt_trades', 'entry_time');

CREATE INDEX idx_crt_symbol_tf ON crt_trades(symbol, timeframe);
CREATE INDEX idx_crt_direction ON crt_trades(direction);
-- Índice GIN para búsquedas ultra rápidas dentro del JSON en el futuro
CREATE INDEX idx_crt_htf_context ON crt_trades USING GIN (htf_context);
