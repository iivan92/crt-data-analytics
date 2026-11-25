//+------------------------------------------------------------------+
//|                          CRT_Analyzer_Liq_Bias_V22.mq5           |
//|    Matriz Definitiva: Zonas de Liquidez vs 9 Escenarios de Bias  |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "22.00"
#property script_show_inputs

input int InpHistoryBars = 3000;
input double InpMinRangePips = 5.0;

// Horarios de Sesión (Hora del Bróker)
input int AsiaStartHour = 0;
input int AsiaEndHour   = 8;  
input int LonStartHour  = 10;
input int LonEndHour    = 14; 

void OnStart()
{
    Print("=====================================================================");
    Print(" INICIANDO THE ULTIMATE NEXUS V22 PARA: ", _Symbol);
    Print(" Fusionando Piscinas de Liquidez y 9 Escenarios de Bias (RUNS FIX)");
    Print("=====================================================================");

    ENUM_TIMEFRAMES timeframes[] = {PERIOD_H12, PERIOD_H8, PERIOD_H4};
    for(int t = 0; t < ArraySize(timeframes); t++) {
        Print("--- TIMEFRAME OPERATIVO: ", EnumToString(timeframes[t]), " ---");
        AnalyzeLiquidityMatrix(timeframes[t]);
        Print("---------------------------------------");
    }
    Print("================= FIN DEL NEXUS V22 ==================");
}

// Función HTF corregida para RUNS (cO <= pH y cO >= pL)
int GetHTFBias(string symbol, ENUM_TIMEFRAMES htf, datetime currentTime) {
    double pointSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double pipsMultiplier = (pointSize == 0.001 || pointSize == 0.00001) ? 10.0 : 1.0;
    int shift = iBarShift(symbol, htf, currentTime);
    if(shift < 0) return 0; 
    
    MqlRates rates[]; ArraySetAsSeries(rates, true);
    if(CopyRates(symbol, htf, shift + 1, 80, rates) < 5) return 0;

    for(int i = 0; i < ArraySize(rates) - 1; i++) {
        double pO = rates[i+1].open, pH = rates[i+1].high, pL = rates[i+1].low, pC = rates[i+1].close;
        double cO = rates[i].open, cH = rates[i].high, cL = rates[i].low, cC = rates[i].close;
        double rBase = pH - pL;
        if((rBase / (pointSize * pipsMultiplier)) < InpMinRangePips) continue;

        int bias = 0; double sl = 0, tp = 0;
        
        if(cL < pL && cC > pL && cC < pH)      { bias = 1; sl = cL; tp = pH; } 
        else if(cH > pH && cC < pH && cC > pL) { bias = -1; sl = cH; tp = pL; } 
        else if(cO <= pH && cC > pH)           { bias = 1; sl = cL; tp = MathMax(pH + (rBase * 0.618), cH); } 
        else if(cO >= pL && cC < pL)           { bias = -1; sl = cH; tp = MathMin(pL - (rBase * 0.618), cL); } 

        if(bias != 0) {
            bool isAlive = true;
            for(int j = i - 1; j >= 0; j--) {
                if(bias == 1) { if(rates[j].low <= sl || rates[j].high >= tp) { isAlive = false; break; } }
                else          { if(rates[j].high >= sl || rates[j].low <= tp) { isAlive = false; break; } }
            }
            return isAlive ? bias : 0; 
        }
    }
    return 0;
}

void AnalyzeLiquidityMatrix(ENUM_TIMEFRAMES curTF)
{
    MqlRates rates[]; ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, curTF, 0, InpHistoryBars, rates);
    if(copied < 10) return;

    // Estructura: [4 Patrones][3 Zonas Liquidez][3 Resultados: Total, Win, Loss]
    // Patrones: 0=BullSwp, 1=BearSwp, 2=BullRun, 3=BearRun
    // Liquidez: 0=Weekly, 1=Daily, 2=Session (Asia/London combinados)
    int c1[4][3][3]; ArrayInitialize(c1, 0); // 🥇 D1 yes, W1 yes
    int c2[4][3][3]; ArrayInitialize(c2, 0); // 🥈 D1 yes, W1 no
    int c3[4][3][3]; ArrayInitialize(c3, 0); // 🥈 D1 yes, W1 neutral
    int c4[4][3][3]; ArrayInitialize(c4, 0); // 🥉 D1 no, W1 yes
    int c5[4][3][3]; ArrayInitialize(c5, 0); // 🥉 D1 neutral, W1 yes
    int c6[4][3][3]; ArrayInitialize(c6, 0); // ❌ D1 no, W1 no
    int c7[4][3][3]; ArrayInitialize(c7, 0); // ❌ D1 no, W1 neutral
    int c8[4][3][3]; ArrayInitialize(c8, 0); // ❌ D1 neutral, W1 no
    int c9[4][3][3]; ArrayInitialize(c9, 0); // ⚖️ Ambos Neutrales

    for(int i = copied - 2; i >= 1; i--)
    {
        datetime time = rates[i].time;
        int biasW1 = GetHTFBias(_Symbol, PERIOD_W1, time);
        int biasD1 = GetHTFBias(_Symbol, PERIOD_D1, time);
        
        datetime dayStart = time - (time % 86400);
        
        int wIdx = iBarShift(_Symbol, PERIOD_W1, time) + 1;
        double pwh = (wIdx > 0) ? iHigh(_Symbol, PERIOD_W1, wIdx) : 0;
        double pwl = (wIdx > 0) ? iLow(_Symbol, PERIOD_W1, wIdx) : 999999;
        
        int dIdx = iBarShift(_Symbol, PERIOD_D1, time) + 1;
        double pdh = (dIdx > 0) ? iHigh(_Symbol, PERIOD_D1, dIdx) : 0;
        double pdl = (dIdx > 0) ? iLow(_Symbol, PERIOD_D1, dIdx) : 999999;

        double sesH = 0, sesL = 999999;
        // Extracción de niveles de Asia y Londres
        datetime aEnd = dayStart + AsiaEndHour*3600, aStart = dayStart + AsiaStartHour*3600;
        if(time < aEnd) { aEnd -= 86400; aStart -= 86400; }
        int aStartIdx = iBarShift(_Symbol, PERIOD_M15, aStart), aEndIdx = iBarShift(_Symbol, PERIOD_M15, aEnd);
        if(aStartIdx != -1 && aEndIdx != -1) {
            sesH = MathMax(sesH, iHigh(_Symbol, PERIOD_M15, iHighest(_Symbol, PERIOD_M15, MODE_HIGH, aStartIdx-aEndIdx+1, aEndIdx)));
            sesL = MathMin(sesL, iLow(_Symbol, PERIOD_M15, iLowest(_Symbol, PERIOD_M15, MODE_LOW, aStartIdx-aEndIdx+1, aEndIdx)));
        }
        
        datetime lEnd = dayStart + LonEndHour*3600, lStart = dayStart + LonStartHour*3600;
        if(time < lEnd) { lEnd -= 86400; lStart -= 86400; }
        int lStartIdx = iBarShift(_Symbol, PERIOD_M15, lStart), lEndIdx = iBarShift(_Symbol, PERIOD_M15, lEnd);
        if(lStartIdx != -1 && lEndIdx != -1) {
            sesH = MathMax(sesH, iHigh(_Symbol, PERIOD_M15, iHighest(_Symbol, PERIOD_M15, MODE_HIGH, lStartIdx-lEndIdx+1, lEndIdx)));
            sesL = MathMin(sesL, iLow(_Symbol, PERIOD_M15, iLowest(_Symbol, PERIOD_M15, MODE_LOW, lStartIdx-lEndIdx+1, lEndIdx)));
        }

        double cO = rates[i].open, cH = rates[i].high, cL = rates[i].low, cC = rates[i].close;

        //========================================================
        // EVALUACIÓN DE PATRONES
        //========================================================
        
        // 1. BEAR SWEEP (-1, pat 1)
        if(cH > pwh && cC < pwh)      { EvaluatePattern(rates, i, -1, 1, 0, cH, cL - ((cH - cL) * 0.5), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        else if(cH > pdh && cC < pdh) { EvaluatePattern(rates, i, -1, 1, 1, cH, cL - ((cH - cL) * 0.5), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        else if(cH > sesH && cC < sesH && sesH > 0) { EvaluatePattern(rates, i, -1, 1, 2, cH, cL - ((cH - cL) * 0.5), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        
        // 2. BEAR RUN (-1, pat 3) - ¡RUNS CORREGIDOS!
        if(cO >= pwl && cC < pwl)      { EvaluatePattern(rates, i, -1, 3, 0, cH, cC - ((cH - cL) * 1.618), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        else if(cO >= pdl && cC < pdl) { EvaluatePattern(rates, i, -1, 3, 1, cH, cC - ((cH - cL) * 1.618), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        else if(cO >= sesL && cC < sesL && sesL != 999999) { EvaluatePattern(rates, i, -1, 3, 2, cH, cC - ((cH - cL) * 1.618), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }

        // 3. BULL SWEEP (1, pat 0)
        if(cL < pwl && cC > pwl)      { EvaluatePattern(rates, i, 1, 0, 0, cL, cH + ((cH - cL) * 0.5), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        else if(cL < pdl && cC > pdl) { EvaluatePattern(rates, i, 1, 0, 1, cL, cH + ((cH - cL) * 0.5), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        else if(cL < sesL && cC > sesL && sesL != 999999) { EvaluatePattern(rates, i, 1, 0, 2, cL, cH + ((cH - cL) * 0.5), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        
        // 4. BULL RUN (1, pat 2) - ¡RUNS CORREGIDOS!
        if(cO <= pwh && cC > pwh)      { EvaluatePattern(rates, i, 1, 2, 0, cL, cC + ((cH - cL) * 1.618), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        else if(cO <= pdh && cC > pdh) { EvaluatePattern(rates, i, 1, 2, 1, cL, cC + ((cH - cL) * 1.618), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
        else if(cO <= sesH && cC > sesH && sesH > 0) { EvaluatePattern(rates, i, 1, 2, 2, cL, cC + ((cH - cL) * 1.618), biasD1, biasW1, c1, c2, c3, c4, c5, c6, c7, c8, c9); }
    }
    
    Print("============= MATRIZ DE BIAS EN PISCINAS DE LIQUIDEZ ===============");
    PrintCategory("🥇 ALINEACIÓN TOTAL (A favor D1 y W1)", c1);
    Print("--------------------------------------------");
    PrintCategory("🥈 A favor D1, pero EN CONTRA de W1", c2);
    PrintCategory("🥈 A favor D1, pero W1 Neutral", c3);
    Print("--------------------------------------------");
    PrintCategory("🥉 A favor W1, pero EN CONTRA de D1", c4);
    PrintCategory("🥉 A favor W1, pero D1 Neutral", c5);
    Print("--------------------------------------------");
    PrintCategory("❌ EN CONTRA de Ambos (D1 y W1)", c6);
    PrintCategory("❌ En contra D1, W1 Neutral", c7);
    PrintCategory("❌ En contra W1, D1 Neutral", c8);
    PrintCategory("⚖️ AMBOS NEUTRALES (D1 y W1)", c9);
}

void EvaluatePattern(MqlRates &rates[], int i, int dir, int patIdx, int liqIdx, double sl, double tp, int bD1, int bW1, 
                     int &c1[][3][3], int &c2[][3][3], int &c3[][3][3], int &c4[][3][3], int &c5[][3][3], 
                     int &c6[][3][3], int &c7[][3][3], int &c8[][3][3], int &c9[][3][3])
{
    int res = 0;
    for(int j = i - 1; j >= 0; j--) {
        if(dir == 1) { if(rates[j].low <= sl) {res=-1; break;} if(rates[j].high >= tp) {res=1; break;} } 
        else         { if(rates[j].high >= sl) {res=-1; break;} if(rates[j].low <= tp) {res=1; break;} }
    }
    
    if(res != 0) {
        int win = (res == 1) ? 1 : 0;
        int loss = (res == -1) ? 1 : 0;
        
        if(dir == bD1 && dir == bW1)        { c1[patIdx][liqIdx][0]++; c1[patIdx][liqIdx][1]+=win; c1[patIdx][liqIdx][2]+=loss; }
        else if(dir == bD1 && bW1 == -dir)  { c2[patIdx][liqIdx][0]++; c2[patIdx][liqIdx][1]+=win; c2[patIdx][liqIdx][2]+=loss; }
        else if(dir == bD1 && bW1 == 0)     { c3[patIdx][liqIdx][0]++; c3[patIdx][liqIdx][1]+=win; c3[patIdx][liqIdx][2]+=loss; }
        else if(bD1 == -dir && dir == bW1)  { c4[patIdx][liqIdx][0]++; c4[patIdx][liqIdx][1]+=win; c4[patIdx][liqIdx][2]+=loss; }
        else if(bD1 == 0 && dir == bW1)     { c5[patIdx][liqIdx][0]++; c5[patIdx][liqIdx][1]+=win; c5[patIdx][liqIdx][2]+=loss; }
        else if(bD1 == -dir && bW1 == -dir) { c6[patIdx][liqIdx][0]++; c6[patIdx][liqIdx][1]+=win; c6[patIdx][liqIdx][2]+=loss; }
        else if(bD1 == -dir && bW1 == 0)    { c7[patIdx][liqIdx][0]++; c7[patIdx][liqIdx][1]+=win; c7[patIdx][liqIdx][2]+=loss; }
        else if(bD1 == 0 && bW1 == -dir)    { c8[patIdx][liqIdx][0]++; c8[patIdx][liqIdx][1]+=win; c8[patIdx][liqIdx][2]+=loss; }
        else if(bD1 == 0 && bW1 == 0)       { c9[patIdx][liqIdx][0]++; c9[patIdx][liqIdx][1]+=win; c9[patIdx][liqIdx][2]+=loss; }
    }
}

void PrintCategory(string title, int &stats[][3][3]) {
    Print(title);
    string pats[4] = {"🟢 BULL SWP", "🔴 BEAR SWP", "🚀 BULL RUN", "☄️ BEAR RUN"};
    for(int p=0; p<4; p++) {
        int tW = stats[p][0][0], wW = stats[p][0][1]; double wrW = tW>0 ? ((double)wW/tW)*100 : 0;
        int tD = stats[p][1][0], wD = stats[p][1][1]; double wrD = tD>0 ? ((double)wD/tD)*100 : 0;
        int tS = stats[p][2][0], wS = stats[p][2][1]; double wrS = tS>0 ? ((double)wS/tS)*100 : 0;
        
        if(tW > 0 || tD > 0 || tS > 0) {
            PrintFormat("   %s | W1-Liq: T:%3d W:%3d [%.1f%%] | D1-Liq: T:%3d W:%3d [%.1f%%] | Ses-Liq: T:%3d W:%3d [%.1f%%]",
                pats[p], tW, wW, wrW, tD, wD, wrD, tS, wS, wrS);
        }
    }
}
//+------------------------------------------------------------------+