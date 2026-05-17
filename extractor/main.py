import MetaTrader5 as mt5
import pandas as pd
import requests
import time
import os
from datetime import datetime, timezone
from dotenv import load_dotenv

# Cargar variables de entorno
load_dotenv()

API_URL = os.getenv("API_URL", "http://localhost:3000/api/v1/trades")
SYMBOLS = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD", "USTEC"] # Pares a analizar
TIMEFRAMES = {
    "H4": mt5.TIMEFRAME_H4,
    "H8": mt5.TIMEFRAME_H8,
    "H12": mt5.TIMEFRAME_H12,
    "D1": mt5.TIMEFRAME_D1,
    "W1": mt5.TIMEFRAME_W1,
    "M1": mt5.TIMEFRAME_M1
}
HISTORY_BARS = 5000
MIN_PIPS = 5.0

def connect_mt5():
    # Ruta específica del MetaTrader que queremos utilizar
    mt5_path = r"C:\Program Files\MetaTrader 5\terminal64.exe"
    
    if not mt5.initialize(mt5_path):
        print("Fallo al inicializar MT5 en la ruta:", mt5_path)
        print("Error =", mt5.last_error())
        return False
    print("MT5 inicializado correctamente en:", mt5_path)
    return True

def get_pip_value(symbol):
    info = mt5.symbol_info(symbol)
    if info is None:
        return None
    # Cálculo estándar del tamaño del pip
    if info.digits == 5 or info.digits == 3:
        return info.point * 10
    return info.point

def get_rates(symbol, tf_constant, count):
    rates = mt5.copy_rates_from_pos(symbol, tf_constant, 0, count)
    if rates is None or len(rates) == 0:
        return pd.DataFrame()
    
    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s', utc=True)
    return df

def analyze_crt(df, symbol, tf_name, pip_value):
    """
    Núcleo del algoritmo CRT adaptado de MQL5 a Pandas (Python).
    Identifica las velas base, evalúa sweeps, y determina el TP/SL.
    """
    trades = []
    
    limit = len(df) - 2
    if limit <= 0:
        return trades

    i = 0 # Iterando cronológicamente de pasado a presente

    while i < limit:
        # Vela actual como posible Vela Base
        base_h = df.loc[i, 'high']
        base_l = df.loc[i, 'low']
        
        if (base_h - base_l) < MIN_PIPS * pip_value:
            i += 1
            continue

        state = 0 
        sweeps = 0
        current_sl = 0.0
        target_full = 0.0
        target_50 = 0.0
        trigger_extreme = 0.0
        has_restarted = False
        hit_50_percent = False
        break_k = -1 
        
        entry_time = None
        direction = ""
        result_type = ""

        # k avanza en el tiempo buscando la activación y resolución
        for k in range(i + 1, len(df)):
            c_h = df.loc[k, 'high']
            c_l = df.loc[k, 'low']
            c_c = df.loc[k, 'close']
            c_o = df.loc[k, 'open']
            c_time = df.loc[k, 'time']

            # === ESTADO 0: ESPERANDO ACTIVACIÓN ===
            if state == 0:
                if c_c > base_h or c_c < base_l:
                    break_k = k
                    break

                # BARRIDA ALCISTA (BULL)
                if c_l < base_l and base_l <= c_c <= base_h:
                    state = 1
                    sweeps = 1
                    has_restarted = False
                    hit_50_percent = False
                    current_sl = c_l
                    target_full = base_h
                    trigger_extreme = c_h
                    target_50 = base_l + (base_h - base_l) * 0.5
                    entry_time = c_time
                    direction = "BULL"
                    
                    if c_h >= target_50:
                        hit_50_percent = True
                    
                    if c_h >= target_full:
                        result_type = "TP_EXPANSION"
                        break_k = k
                        break
                
                # BARRIDA BAJISTA (BEAR)
                elif c_h > base_h and base_l <= c_c <= base_h:
                    state = -1
                    sweeps = 1
                    has_restarted = False
                    hit_50_percent = False
                    current_sl = c_h
                    target_full = base_l
                    trigger_extreme = c_l
                    target_50 = base_h - (base_h - base_l) * 0.5
                    entry_time = c_time
                    direction = "BEAR"
                    
                    if c_l <= target_50:
                        hit_50_percent = True
                    
                    if c_l <= target_full:
                        result_type = "TP_EXPANSION"
                        break_k = k
                        break

            # === ESTADO 1: BULLISH ACTIVO ===
            elif state == 1:
                if c_h >= target_50:
                    hit_50_percent = True

                is_tp = c_h >= target_full
                is_sl = c_l <= current_sl

                if is_tp and is_sl:
                    if abs(c_o - current_sl) <= abs(target_full - c_o):
                        is_tp = False
                    else:
                        is_sl = False

                if is_tp:
                    result_type = "TP_REINICIO" if has_restarted else "TP_EXPANSION"
                    break_k = k
                    break
                elif is_sl:
                    if base_l <= c_c <= base_h:
                        sweeps += 1
                        current_sl = c_l
                        trigger_extreme = max(trigger_extreme, c_h)
                        has_restarted = False
                        if c_h >= target_50:
                            hit_50_percent = True
                    else:
                        result_type = "SL"
                        break_k = k
                        break
                elif not has_restarted:
                    if c_h > trigger_extreme and c_c < trigger_extreme:
                        has_restarted = True # Trampa bajista (Reinicio)

            # === ESTADO -1: BEARISH ACTIVO ===
            elif state == -1:
                if c_l <= target_50:
                    hit_50_percent = True

                is_tp = c_l <= target_full
                is_sl = c_h >= current_sl

                if is_tp and is_sl:
                    if abs(c_o - current_sl) <= abs(c_o - target_full):
                        is_tp = False
                    else:
                        is_sl = False

                if is_tp:
                    result_type = "TP_REINICIO" if has_restarted else "TP_EXPANSION"
                    break_k = k
                    break
                elif is_sl:
                    if base_l <= c_c <= base_h:
                        sweeps += 1
                        current_sl = c_h
                        trigger_extreme = min(trigger_extreme, c_l)
                        has_restarted = False
                        if c_l <= target_50:
                            hit_50_percent = True
                    else:
                        result_type = "SL"
                        break_k = k
                        break
                elif not has_restarted:
                    if c_l < trigger_extreme and c_c > trigger_extreme:
                        has_restarted = True # Trampa alcista (Reinicio)

        if state != 0 and result_type != "":
            exit_time = df.loc[max(0, break_k), 'time']
            trade = {
                "symbol": symbol,
                "timeframe": tf_name,
                "direction": direction,
                "entry_time": entry_time.strftime('%Y-%m-%dT%H:%M:%SZ'),
                "exit_time": exit_time.strftime('%Y-%m-%dT%H:%M:%SZ'),
                "base_high": round(base_h, 5),
                "base_low": round(base_l, 5),
                "trigger_extreme": round(trigger_extreme, 5),
                "sweep_count": sweeps,
                "has_restarted": has_restarted,
                "hit_50_percent": hit_50_percent,
                "result_type": result_type,
                "mae": 0.0,
                "mfe": 0.0,
                "htf_context": {},
                "metadata": {"source": "Python_Extractor_Win"}
            }
            trades.append(trade)

        if break_k != -1:
            i = break_k
        else:
            i += 1
            
    return trades

def send_to_api(trades):
    if not trades:
        print("  -> No hay trades para enviar en este periodo/par.")
        return
    
    headers = {"Content-Type": "application/json"}
    
    # Aseguramos que la URL termine en /batch
    batch_url = API_URL
    if not batch_url.endswith('/batch'):
        # Si la API_URL es algo como .../trades, le añadimos /batch
        batch_url = batch_url.rstrip('/') + '/batch'
        
    print(f"  -> Iniciando subida BATCH de {len(trades)} trades a {batch_url}...")
    
    try:
        # Enviamos la lista completa de trades de una vez
        response = requests.post(batch_url, json=trades, headers=headers, timeout=30)
        
        if response.status_code == 201:
            print(f"  -> BATCH Subida completada: {len(trades)} trades insertados con éxito.")
        else:
            print(f"  -> BATCH Error de API: {response.text}")
    except Exception as e:
        print(f"  -> BATCH Error de conexión: {e}")

def run_extraction():
    if not connect_mt5():
        return
        
    for symbol in SYMBOLS:
        pip_value = get_pip_value(symbol)
        if not pip_value:
            print(f"No se pudo obtener el valor del pip para {symbol}")
            continue
            
        print(f"--- Procesando {symbol} ---")
        for tf_name, tf_const in TIMEFRAMES.items():
            print(f" Obteniendo datos para {symbol} {tf_name}...")
            df = get_rates(symbol, tf_const, HISTORY_BARS)
            if not df.empty:
                print(f"  -> {len(df)} velas descargadas. Analizando...")
                trades = analyze_crt(df, symbol, tf_name, pip_value)
                print(f"  -> {len(trades)} trades encontrados localmente.")
                send_to_api(trades)
            else:
                print(f"  -> No se obtuvieron datos (velas vacías) para {symbol} {tf_name}")
                
    mt5.shutdown()
    print("=== Extracción finalizada ===")

if __name__ == "__main__":
    print("Iniciando servicio extractor de MT5 (CRT)...")
    run_extraction()
