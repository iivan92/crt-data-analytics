//+------------------------------------------------------------------+
//|                          CRT_Analyzer_LTF_Bias_V27.mq5           |
//|    Filtro Definitivo: Anticipación LTF vs Escenarios de Bias     |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo SMC"
#property version   "27.00"
#property script_show_inputs

input int InpHistoryBars = 1000;    
input double InpMinRangePips = 5.0; 

void OnStart()
{
    Print("=====================================================================");
    Print(" INICIANDO TESTER DE FRICCIÓN LTF V27 PARA: ", _Symbol);
    Print(" Cruzando Gatillos LTF con 5 Escenarios de Bias Institucional");
    Print("=====================================================================");

    ENUM_TIMEFRAMES mtfs[] = {PERIOD_H12, PERIOD_H8, PERIOD_H4};
    ENUM_TIMEFRAMES ltfs[] = {PERIOD_H1, PERIOD_M15, PERIOD_M5};

    for(int m = 0; m < ArraySize(mtfs); m++)
    {
        Print("=====================================================================");
        Print(" 🔍 CONTEXTO MTF: ", EnumToString(mtfs[m]));
        Print("=====================================================================");
        
        for(int l = 0; l < ArraySize(ltfs); l++)
        {
            if(mtfs[m] == ltfs[l]) continue;
            if(mtfs[m] == PERIOD_H4 && ltfs[l] == PERIOD_H12) continue; 
            
            Print("   >>> GATILLO LTF: ", EnumToString(ltfs[l]));
            AnalyzeSweepsWithBias(mtfs[m], ltfs[l]);
            Print("   ---------------------------------------------------------------");
        }
    }
    Print("================= FIN DEL AUTO-TESTER V27 ==================");
}

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

void AnalyzeSweepsWithBias(ENUM_TIMEFRAMES InpMTF, ENUM_TIMEFRAMES InpLTF)
{
    MqlRates ratesMTF[]; ArraySetAsSeries(ratesMTF, true);
    int copiedMTF = CopyRates(_Symbol, InpMTF, 0, InpHistoryBars, ratesMTF);
    if(copiedMTF < 10) return; 

    // Matrices [6 Categorías de Bias][4 Stats: Total, Win, Loss, Cut]
    int bearSwp[6][4]; ArrayInitialize(bearSwp, 0);
    int bullSwp[6][4]; ArrayInitialize(bullSwp, 0);

    for(int i = copiedMTF - 3; i >= 1; i--)
    {
        datetime mtfTime = ratesMTF[i].time;
        datetime mtfEndTime = ratesMTF[i-1].time; 
        
        int biasW1 = GetHTFBias(_Symbol, PERIOD_W1, mtfTime);
        int biasD1 = GetHTFBias(_Symbol, PERIOD_D1, mtfTime);
        
        int dIdx = iBarShift(_Symbol, PERIOD_D1, mtfTime) + 1;
        double pdh = (dIdx > 0) ? iHigh(_Symbol, PERIOD_D1, dIdx) : 0;
        double pdl = (dIdx > 0) ? iLow(_Symbol, PERIOD_D1, dIdx) : 999999;

        double mtfClose = ratesMTF[i].close;
        double pMtfH = ratesMTF[i+1].high, pMtfL = ratesMTF[i+1].low;
        double pRangeMid = pMtfL + (pMtfH - pMtfL) * 0.5;
        
        MqlRates ratesLTF[]; ArraySetAsSeries(ratesLTF, true);
        int shiftStart = iBarShift(_Symbol, InpLTF, mtfTime);
        int shiftEnd = iBarShift(_Symbol, InpLTF, mtfEndTime);

        if(shiftStart == -1 || shiftEnd == -1 || shiftStart <= shiftEnd) continue;
        int ltfCount = shiftStart - shiftEnd;

        int copiedLTF = CopyRates(_Symbol, InpLTF, shiftEnd, ltfCount + 2, ratesLTF); 
        
        if(copiedLTF >= 2) 
        {
            datetime nextAllowedEntry = 0;
            int safeStart = (int)MathMin((double)ltfCount, (double)(copiedLTF - 2));

            for(int j = safeStart; j >= 1; j--)
            {
                if(ratesLTF[j].time <= nextAllowedEntry) continue;

                double pLtfH = ratesLTF[j+1].high, pLtfL = ratesLTF[j+1].low;
                double cLtfO = ratesLTF[j].open, cLtfC = ratesLTF[j].close, cLtfH = ratesLTF[j].high, cLtfL = ratesLTF[j].low;

                // --- ANTICIPAR BEAR SWEEP (VENTA -> DIR = -1) ---
                if(cLtfH > pdh && cLtfH > pLtfH && cLtfC < cLtfO) {
                    double sl = cLtfH; double tp = pRangeMid; 
                    bool mtfInvalidates = (mtfClose > pdh); 
                    
                    int cat = GetCategory(-1, biasW1, biasD1);
                    datetime exitTime = 0;
                    int res = SimulateSequential(ratesLTF, j-1, -1, cLtfC, sl, tp, mtfEndTime, mtfInvalidates, exitTime);
                    
                    if(res != 0) {
                        RecordResult(bearSwp, 0, res); // Registrar en BASE
                        RecordResult(bearSwp, cat, res); // Registrar en Categoría Específica
                        nextAllowedEntry = exitTime;
                    }
                }
                // --- ANTICIPAR BULL SWEEP (COMPRA -> DIR = 1) ---
                else if(cLtfL < pdl && cLtfL < pLtfL && cLtfC > cLtfO) {
                    double sl = cLtfL; double tp = pRangeMid; 
                    bool mtfInvalidates = (mtfClose < pdl); 
                    
                    int cat = GetCategory(1, biasW1, biasD1);
                    datetime exitTime = 0;
                    int res = SimulateSequential(ratesLTF, j-1, 1, cLtfC, sl, tp, mtfEndTime, mtfInvalidates, exitTime);
                    
                    if(res != 0) {
                        RecordResult(bullSwp, 0, res); // Registrar en BASE
                        RecordResult(bullSwp, cat, res); // Registrar en Categoría Específica
                        nextAllowedEntry = exitTime;
                    }
                }
            }
        }
    }

    PrintResults("🔴 BEAR SWEEPS (Ventas Anticiapadas)", bearSwp);
    PrintResults("🟢 BULL SWEEPS (Compras Anticipadas)", bullSwp);
}

// 0: Base, 1: Align All, 2: Fric W1, 3: Fric D1, 4: Contra All, 5: Neutral
int GetCategory(int dir, int bW1, int bD1) {
    if(bW1 == 0 || bD1 == 0) return 5;
    if(dir == bW1 && dir == bD1) return 1;
    if(dir == bW1 && dir != bD1) return 2;
    if(dir != bW1 && dir == bD1) return 3;
    if(dir != bW1 && dir != bD1) return 4;
    return 5;
}

void RecordResult(int &stats[][4], int cat, int res) {
    stats[cat][0]++;
    if(res == 1) stats[cat][1]++;
    else if(res == -1) stats[cat][2]++;
    else stats[cat][3]++;
}

int SimulateSequential(MqlRates &ratesLTF[], int startIndex, int type, double entry, double sl, double tp, datetime maxTime, bool mtfInvalidates, datetime &outExitTime) 
{
    for(int k = startIndex; k >= 0; k--) {
        outExitTime = ratesLTF[k].time;
        if(type == 1) { 
            if(ratesLTF[k].low <= sl) return -1;
            if(ratesLTF[k].high >= tp) return 1;
        } else { 
            if(ratesLTF[k].high >= sl) return -1;
            if(ratesLTF[k].low <= tp) return 1;
        }
        if(ratesLTF[k].time >= maxTime && mtfInvalidates) {
            double cClose = ratesLTF[k].close;
            if(type == 1) return (cClose >= entry) ? 2 : -2;  
            if(type == -1) return (cClose <= entry) ? 2 : -2; 
        }
    }
    return 0; 
}

void PrintResults(string title, int &stats[][4]) {
    Print("   ", title);
    string labels[6] = {"BASE (Sin filtro)", "🥇 Alineación Total", "🥉 Fricción (Pro-W1, vs D1)", "🥈 Fricción (Pro-D1, vs W1)", "❌ En contra de Ambos", "⚖️ Bias Neutral"};
    
    for(int i = 0; i < 6; i++) {
        if(stats[i][0] > 0) {
            double wr = ((double)stats[i][1] / stats[i][0]) * 100.0;
            PrintFormat("      %s | T: %3d | W: %3d | L: %3d | C: %3d | WR: %.1f%%", labels[i], stats[i][0], stats[i][1], stats[i][2], stats[i][3], wr);
        }
    }
}
//+------------------------------------------------------------------+