# Contexto del Proyecto: CRT Quant Infrastructure

## 1. Visión General

Este proyecto es una infraestructura institucional de datos cuantitativos para analizar el rendimiento de la estrategia mecánica "Candle Range Theory" (CRT). El sistema ingiere datos estructurados enviados en tiempo real o en lotes desde MetaTrader 5 (MT5), los almacena para análisis de series temporales y permite su visualización y modelado estadístico avanzado.

## 2. Dominio y Reglas de Negocio (CRT)

El sistema evalúa "Setups" basados en la acción del precio y la liquidez. Los conceptos clave que la IA debe entender al generar código son:

- **Vela Base (Base Candle):** Una vela que define un rango operativo (Alto y Bajo).
- **Sweep (Barrida):** Cuando el precio supera el extremo de la Vela Base pero _cierra dentro_ de ella. Esto activa el trade.
  - _Bull Sweep:_ Toma de liquidez inferior. Genera compra.
  - _Bear Sweep:_ Toma de liquidez superior. Genera venta.
- **Sweeps Múltiples:** El precio puede barrer el extremo varias veces (Sweep 1, 2, 3+). Si sigue cerrando dentro, el setup sigue vivo.
- **Rango Reiniciado (Restart):** Ocurre si el precio llega al Take Profit pero falla en romper la estructura (cierra dentro del rango), generando una barrida en contra. Es una variable crítica para evaluar la toxicidad del setup.
- **Contexto Multi-Timeframe (HTF Bias):** Un setup en una temporalidad menor (ej. M15) puede estar respaldado o bloqueado por lo que ocurre en temporalidades mayores (ej. H4, D1). Este contexto dinámico se registra para estudios estadísticos cruzados.
- **Resultados Posibles:** \* `TP_EXPANSION`: Llega a TP y rompe el rango.
  - `TP_REINICIO`: Llega a TP pero genera un reinicio.
  - `SL`: Toca el Stop Loss (extremo del Sweep).
  - `DESCARTADO`: El rango se invalida por cierre en contra prematuro.

## 3. Flujo de Datos

1. **Extracción (Windows):** Un servicio extractor escrito en Python (`extractor/`) se conecta a las terminales de MetaTrader 5 locales, descarga datos históricos (`copy_rates_from_pos`), procesa los Setups CRT, y genera lotes en formato JSON.
2. **Ingesta (Linux):** El extractor envía el payload JSON a la API (Node.js). La API recibe, valida (Zod) y guarda los trades en TimescaleDB, incluyendo la data dinámica (JSONB).
3. **Análisis (Linux/Local):** El entorno de análisis (Python/Grafana) consulta estos datos almacenados para extraer métricas complejas y relaciones cruzadas entre temporalidades.
