//+------------------------------------------------------------------+
//|                          CRT_Analyzer_AutoLTF_V26_1.mq5          |
//|    Matriz Automática de Gatillos (Con Protección de Arrays)      |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo SMC"
#property version   "26.01"
#property script_show_inputs

input int InpHistoryBars = 1000;    // Velas MTF a analizar
input double InpMinRangePips = 5.0; // Filtro de ruido MTF

void OnStart()
{
    Print("=====================================================================");
    Print(" INICIANDO AUTO-TESTER LTF V26.1 (Safe-Arrays) PARA: ", _Symbol);
    Print(" Evaluando combinaciones MTF (H12,H8,H4) con LTF (H1,M15,M5)");
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
            // Evitamos comparar el mismo timeframe o un LTF mayor al MTF
            if(mtfs[m] == ltfs[l]) continue;
            if(mtfs[m] == PERIOD_H4 && ltfs[l] == PERIOD_H12) continue; // Por seguridad lógica
            
            Print("   >>> GATILLO LTF: ", EnumToString(ltfs[l]));
            AnalyzeCombination(mtfs[m], ltfs[l]);
            Print("   ---------------------------------------------------------------");
        }
    }
    Print("================= FIN DEL AUTO-TESTER V26.1 ==================");
}

void AnalyzeCombination(ENUM_TIMEFRAMES InpMTF, ENUM_TIMEFRAMES InpLTF)
{
    MqlRates ratesMTF[]; ArraySetAsSeries(ratesMTF, true);
    int copiedMTF = CopyRates(_Symbol, InpMTF, 0, InpHistoryBars, ratesMTF);
    if(copiedMTF < 10) return; // Aseguramos que haya datos MTF

    // Contadores: Total, Wins (TP), Losses (SL), Cut (Inv)
    int swpBear[4] = {0,0,0,0}; int swpBull[4] = {0,0,0,0};
    int runBear[4] = {0,0,0,0}; int runBull[4] = {0,0,0,0};

    double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double pipsMult = (pointSize == 0.001 || pointSize == 0.00001) ? 10.0 : 1.0;

    // Bucle seguro usando copiedMTF en lugar de InpHistoryBars fijo
    for(int i = copiedMTF - 3; i >= 1; i--)
    {
        datetime mtfTime = ratesMTF[i].time;
        datetime mtfEndTime = ratesMTF[i-1].time; // Límite de tiempo
        
        // Niveles D1 (PDH / PDL)
        int dIdx = iBarShift(_Symbol, PERIOD_D1, mtfTime) + 1;
        double pdh = (dIdx > 0) ? iHigh(_Symbol, PERIOD_D1, dIdx) : 0;
        double pdl = (dIdx > 0) ? iLow(_Symbol, PERIOD_D1, dIdx) : 999999;

        double mtfClose = ratesMTF[i].close;
        double pMtfH = ratesMTF[i+1].high, pMtfL = ratesMTF[i+1].low;
        double pRangeMid = pMtfL + (pMtfH - pMtfL) * 0.5;
        
        MqlRates ratesLTF[]; ArraySetAsSeries(ratesLTF, true);
        int shiftStart = iBarShift(_Symbol, InpLTF, mtfTime);
        int shiftEnd = iBarShift(_Symbol, InpLTF, mtfEndTime);

        // Seguridad fundamental: verificamos índices válidos
        if(shiftStart == -1 || shiftEnd == -1 || shiftStart <= shiftEnd) continue;
        int ltfCount = shiftStart - shiftEnd;

        // --- 1. MÓDULO: ANTICIPAR SWEEPS ---
        int copiedLTF = CopyRates(_Symbol, InpLTF, shiftEnd, ltfCount + 2, ratesLTF); 
        
        // Solo operamos si descargó al menos 2 velas LTF para poder comparar
        if(copiedLTF >= 2) 
        {
            datetime nextAllowedEntry = 0;
            // Límite seguro para no pedir [j+1] fuera del array descargado
            int safeStart = (int)MathMin((double)ltfCount, (double)(copiedLTF - 2));

            for(int j = safeStart; j >= 1; j--)
            {
                if(ratesLTF[j].time <= nextAllowedEntry) continue;

                double pLtfH = ratesLTF[j+1].high, pLtfL = ratesLTF[j+1].low;
                double cLtfO = ratesLTF[j].open, cLtfC = ratesLTF[j].close, cLtfH = ratesLTF[j].high, cLtfL = ratesLTF[j].low;

                // ANTICIPAR BEAR SWEEP en PDH
                if(cLtfH > pdh && cLtfH > pLtfH && cLtfC < cLtfO) {
                    double sl = cLtfH; 
                    double tp = pRangeMid; 
                    bool mtfInvalidates = (mtfClose > pdh); 
                    
                    datetime exitTime = 0;
                    int res = SimulateSequential(ratesLTF, j-1, -1, cLtfC, sl, tp, mtfEndTime, mtfInvalidates, exitTime);
                    if(res != 0) {
                        swpBear[0]++; if(res == 1) swpBear[1]++; else if(res == -1) swpBear[2]++; else swpBear[3]++;
                        nextAllowedEntry = exitTime;
                    }
                }
                // ANTICIPAR BULL SWEEP en PDL
                else if(cLtfL < pdl && cLtfL < pLtfL && cLtfC > cLtfO) {
                    double sl = cLtfL;
                    double tp = pRangeMid; 
                    bool mtfInvalidates = (mtfClose < pdl); 
                    
                    datetime exitTime = 0;
                    int res = SimulateSequential(ratesLTF, j-1, 1, cLtfC, sl, tp, mtfEndTime, mtfInvalidates, exitTime);
                    if(res != 0) {
                        swpBull[0]++; if(res == 1) swpBull[1]++; else if(res == -1) swpBull[2]++; else swpBull[3]++;
                        nextAllowedEntry = exitTime;
                    }
                }
            }
        }

        // --- 2. MÓDULO: PULLBACKS DE RUNS ---
        double baseMtfH = ratesMTF[i+2].high, baseMtfL = ratesMTF[i+2].low;
        double runMtfO = ratesMTF[i+1].open, runMtfC = ratesMTF[i+1].close;
        double runMtfH = ratesMTF[i+1].high, runMtfL = ratesMTF[i+1].low;
        double rBase = baseMtfH - baseMtfL;
        
        if((rBase / (pointSize * pipsMult)) >= InpMinRangePips)
        {
            int runDir = 0;
            // Evaluamos si la vela MTF ANTERIOR confirmó un Run
            if(runMtfO <= baseMtfH && runMtfC > baseMtfH) runDir = 1;      
            else if(runMtfO >= baseMtfL && runMtfC < baseMtfL) runDir = -1; 

            if(runDir != 0 && copiedLTF >= 2)
            {
                datetime nextAllowedEntry = 0;
                int safeStartRun = (int)MathMin((double)ltfCount, (double)(copiedLTF - 2));

                for(int j = safeStartRun; j >= 1; j--)
                {
                    if(ratesLTF[j].time <= nextAllowedEntry) continue;

                    double pLtfH = ratesLTF[j+1].high, pLtfL = ratesLTF[j+1].low;
                    double cLtfO = ratesLTF[j].open, cLtfC = ratesLTF[j].close, cLtfH = ratesLTF[j].high, cLtfL = ratesLTF[j].low;

                    // Pullback Bull Run
                    if(runDir == 1 && cLtfL < pLtfL && cLtfC > cLtfO) {
                        double sl = runMtfL; 
                        double tp = MathMax(baseMtfH + (rBase * 0.618), runMtfH); 
                        bool mtfInvalidates = (mtfClose < baseMtfH); 
                        
                        datetime exitTime = 0;
                        int res = SimulateSequential(ratesLTF, j-1, 1, cLtfC, sl, tp, mtfEndTime, mtfInvalidates, exitTime);
                        if(res != 0) {
                            runBull[0]++; if(res == 1) runBull[1]++; else if(res == -1) runBull[2]++; else runBull[3]++;
                            nextAllowedEntry = exitTime;
                        }
                    }
                    // Pullback Bear Run
                    else if(runDir == -1 && cLtfH > pLtfH && cLtfC < cLtfO) {
                        double sl = runMtfH; 
                        double tp = MathMin(baseMtfL - (rBase * 0.618), runMtfL); 
                        bool mtfInvalidates = (mtfClose > baseMtfL); 
                        
                        datetime exitTime = 0;
                        int res = SimulateSequential(ratesLTF, j-1, -1, cLtfC, sl, tp, mtfEndTime, mtfInvalidates, exitTime);
                        if(res != 0) {
                            runBear[0]++; if(res == 1) runBear[1]++; else if(res == -1) runBear[2]++; else runBear[3]++;
                            nextAllowedEntry = exitTime;
                        }
                    }
                }
            }
        }
    }

    // --- IMPRESIÓN DE RESULTADOS ---
    double wrBearSwp = (swpBear[0] > 0) ? ((double)swpBear[1] / swpBear[0]) * 100.0 : 0.0;
    double wrBullSwp = (swpBull[0] > 0) ? ((double)swpBull[1] / swpBull[0]) * 100.0 : 0.0;
    double wrBearRun = (runBear[0] > 0) ? ((double)runBear[1] / runBear[0]) * 100.0 : 0.0;
    double wrBullRun = (runBull[0] > 0) ? ((double)runBull[1] / runBull[0]) * 100.0 : 0.0;

    PrintFormat("   🔴 ANTICIPAR BEAR SWP | T: %3d | W: %3d | L: %3d | C: %3d | WR: %.1f%%", swpBear[0], swpBear[1], swpBear[2], swpBear[3], wrBearSwp);
    PrintFormat("   🟢 ANTICIPAR BULL SWP | T: %3d | W: %3d | L: %3d | C: %3d | WR: %.1f%%", swpBull[0], swpBull[1], swpBull[2], swpBull[3], wrBullSwp);
    Print("   - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -");
    PrintFormat("   ☄️ PULLBACK BEAR RUN  | T: %3d | W: %3d | L: %3d | C: %3d | WR: %.1f%%", runBear[0], runBear[1], runBear[2], runBear[3], wrBearRun);
    PrintFormat("   🚀 PULLBACK BULL RUN  | T: %3d | W: %3d | L: %3d | C: %3d | WR: %.1f%%", runBull[0], runBull[1], runBull[2], runBull[3], wrBullRun);
}

// 1 = Win (TP), -1 = Loss (SL), 2/-2 = Cut (Invalidación por MTF)
int SimulateSequential(MqlRates &ratesLTF[], int startIndex, int type, double entry, double sl, double tp, datetime maxTime, bool mtfInvalidates, datetime &outExitTime) 
{
    for(int k = startIndex; k >= 0; k--) {
        outExitTime = ratesLTF[k].time;
        
        if(type == 1) { // COMPRA
            if(ratesLTF[k].low <= sl) return -1;
            if(ratesLTF[k].high >= tp) return 1;
        } else { // VENTA
            if(ratesLTF[k].high >= sl) return -1;
            if(ratesLTF[k].low <= tp) return 1;
        }

        if(ratesLTF[k].time >= maxTime) {
            if(mtfInvalidates) {
                double currentClose = ratesLTF[k].close;
                if(type == 1 && currentClose >= entry) return 2;  
                if(type == 1 && currentClose < entry) return -2; 
                if(type == -1 && currentClose <= entry) return 2; 
                if(type == -1 && currentClose > entry) return -2;
            }
        }
    }
    return 0; 
}
//+------------------------------------------------------------------+