//+------------------------------------------------------------------+
//|                                           CRT_Analyzer_LTF.mq5   |
//|                                    Smart Money Concepts - V21.0  |
//|                    (Ejecución LTF en Niveles H4 - Fixed R:R)     |
//+------------------------------------------------------------------+
#property copyright "SMC Algorithmic Trading"
#property link      ""
#property version   "21.00"
#property script_show_inputs

input ENUM_TIMEFRAMES InpConfirmTF = PERIOD_M15; // Timeframe de Confirmación (Ej. M15 o H1)

void OnStart()
{
    Print("=====================================================================");
    Print(" INICIANDO ANALIZADOR DE EJECUCIÓN LTF V21 : ", _Symbol);
    Print(" Contexto: PERIOD_H4 | Confirmación: ", EnumToString(InpConfirmTF), " | Simulador: PERIOD_M5");
    Print("=====================================================================");

    AnalyzeLTFExecution();
    
    Print("================= FIN DE LA SIMULACIÓN V21 ==================");
}

void AnalyzeLTFExecution()
{
    MqlRates ratesConfirm[];
    ArraySetAsSeries(ratesConfirm, true);
    // Cargamos 5000 velas del TF de confirmación para tener una buena muestra
    int copied = CopyRates(_Symbol, InpConfirmTF, 0, 5000, ratesConfirm);
    if(copied < 10) return;

    // Arrays para guardar resultados: [0] Total, [1] Wins 1:1, [2] Wins 1:2, [3] Wins 1:3, [4] Losses
    int bullStats[5] = {0, 0, 0, 0, 0};
    int bearStats[5] = {0, 0, 0, 0, 0};

    // Recorremos desde el pasado hacia el presente
    for(int i = copied - 2; i >= 2; i--) 
    {
        datetime currentTime = ratesConfirm[i].time;
        
        // 1. Obtener el contexto de H4 (La vela anterior de H4)
        int h4_shift = iBarShift(_Symbol, PERIOD_H4, currentTime);
        if(h4_shift < 0) continue;
        
        double h4_prevHigh = iHigh(_Symbol, PERIOD_H4, h4_shift + 1);
        double h4_prevLow  = iLow(_Symbol, PERIOD_H4, h4_shift + 1);
        
        // 2. Datos de la vela de Confirmación (M15 o H1)
        double confOpen  = ratesConfirm[i].open;
        double confHigh  = ratesConfirm[i].high;
        double confLow   = ratesConfirm[i].low;
        double confClose = ratesConfirm[i].close;

        // Filtro V3 (Cambio de color) - Opcional pero recomendado para mayor WR
        bool isBullClose = confClose > confOpen;
        bool isBearClose = confClose < confOpen;

        int signalDir = 0;
        double entryPrice = 0, slPrice = 0;

        // --- DETECCIÓN BULL SWEEP (Confirmación barre Mínimo H4) ---
        if(confLow < h4_prevLow && confClose > h4_prevLow && isBullClose) {
            signalDir = 1;
            entryPrice = ratesConfirm[i-1].open; // Apertura de la siguiente vela
            slPrice = confLow; // Punta de la mecha
        }
        // --- DETECCIÓN BEAR SWEEP (Confirmación barre Máximo H4) ---
        else if(confHigh > h4_prevHigh && confClose < h4_prevHigh && isBearClose) {
            signalDir = -1;
            entryPrice = ratesConfirm[i-1].open;
            slPrice = confHigh;
        }

        // 3. Simulación de Ratios si hay señal
        if(signalDir != 0) {
            double risk = MathAbs(entryPrice - slPrice);
            if(risk <= 0) continue; // Evitar división por cero
            
            double tp1 = (signalDir == 1) ? entryPrice + risk : entryPrice - risk;
            double tp2 = (signalDir == 1) ? entryPrice + (risk * 2) : entryPrice - (risk * 2);
            double tp3 = (signalDir == 1) ? entryPrice + (risk * 3) : entryPrice - (risk * 3);

            // Llamamos al simulador en M5
            int result = SimulateM5Trade(currentTime, signalDir, entryPrice, slPrice, tp1, tp2, tp3);

            if(signalDir == 1) {
                bullStats[0]++;
                if(result >= 1) bullStats[1]++; // Tocó 1:1
                if(result >= 2) bullStats[2]++; // Tocó 1:2
                if(result >= 3) bullStats[3]++; // Tocó 1:3
                if(result == -1) bullStats[4]++; // Tocó SL antes de 1:1
            } else {
                bearStats[0]++;
                if(result >= 1) bearStats[1]++;
                if(result >= 2) bearStats[2]++;
                if(result >= 3) bearStats[3]++;
                if(result == -1) bearStats[4]++;
            }
        }
    }
    
    // Imprimir Resultados
    PrintResults("🟢 COMPRAS (BULL SWEEPS de H4 confirmados en " + EnumToString(InpConfirmTF) + ")", bullStats);
    PrintResults("🔴 VENTAS (BEAR SWEEPS de H4 confirmados en " + EnumToString(InpConfirmTF) + ")", bearStats);
}

// Simulador en M5: Retorna -1 (SL), 1 (TP1), 2 (TP2), 3 (TP3)
int SimulateM5Trade(datetime startTime, int dir, double entry, double sl, double tp1, double tp2, double tp3)
{
    int maxBarsToCheck = 288; // Max ~24 horas en M5 para darle margen al trade
    int m5_shift = iBarShift(_Symbol, PERIOD_M5, startTime);
    if(m5_shift < 0) return 0;

    MqlRates m5Rates[];
    ArraySetAsSeries(m5Rates, true);
    int copied = CopyRates(_Symbol, PERIOD_M5, m5_shift - 1, maxBarsToCheck, m5Rates);
    
    int highestLevelHit = 0; // 0=Abierto, 1=TP1, 2=TP2, 3=TP3

    for(int j = copied - 1; j >= 0; j--) {
        if(dir == 1) { // Compra
            if(m5Rates[j].low <= sl) return (highestLevelHit > 0) ? highestLevelHit : -1;
            if(m5Rates[j].high >= tp3) return 3;
            if(m5Rates[j].high >= tp2 && highestLevelHit < 2) highestLevelHit = 2;
            if(m5Rates[j].high >= tp1 && highestLevelHit < 1) highestLevelHit = 1;
        } else { // Venta
            if(m5Rates[j].high >= sl) return (highestLevelHit > 0) ? highestLevelHit : -1;
            if(m5Rates[j].low <= tp3) return 3;
            if(m5Rates[j].low <= tp2 && highestLevelHit < 2) highestLevelHit = 2;
            if(m5Rates[j].low <= tp1 && highestLevelHit < 1) highestLevelHit = 1;
        }
    }
    return highestLevelHit; // Si se queda abierto pero tocó algún TP
}

void PrintResults(string title, int &stats[]) {
    int total = stats[0];
    if(total == 0) return;
    
    double wr1 = ((double)stats[1] / total) * 100.0;
    double wr2 = ((double)stats[2] / total) * 100.0;
    double wr3 = ((double)stats[3] / total) * 100.0;
    double lossRate = ((double)stats[4] / total) * 100.0;

    Print(title);
    PrintFormat("   Operaciones Totales : %d", total);
    PrintFormat("   💥 Fallos (Toca SL) : %d (%.1f%%)", stats[4], lossRate);
    PrintFormat("   🎯 Éxito Ratio 1:1  : %d (%.1f%%)", stats[1], wr1);
    PrintFormat("   🚀 Éxito Ratio 1:2  : %d (%.1f%%)", stats[2], wr2);
    PrintFormat("   🔥 Éxito Ratio 1:3  : %d (%.1f%%)", stats[3], wr3);
    Print("------------------------------------------------------");
}
//+------------------------------------------------------------------+