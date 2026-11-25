//+------------------------------------------------------------------+
//|                                            CRT_Analyzer_Bias.mq5 |
//|                                    Smart Money Concepts - V20.0  |
//|                    (Desglose ABSOLUTO de todas las permutaciones)|
//+------------------------------------------------------------------+
#property copyright "SMC Algorithmic Trading"
#property link      ""
#property version   "20.00"
#property script_show_inputs

input double InpMinRangePips = 5.0; // Rango mínimo vela anterior en Pips

void OnStart()
{
    Print("=====================================================================");
    Print(" INICIANDO MATRIX DEFINITIVA V20 (Desglose Total) : ", _Symbol);
    Print("=====================================================================");

    ENUM_TIMEFRAMES timeframes[] = {PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H4};
    int totalTimeframes = ArraySize(timeframes);

    for(int tf = 0; tf < totalTimeframes; tf++)
    {
        Print("--- TIMEFRAME OPERATIVO: ", EnumToString(timeframes[tf]), " ---");
        AnalyzeAlignedTimeframe(timeframes[tf]);
        Print("---------------------------------------");
    }
    Print("================= FIN DE LA MATRIX V20 ==================");
}

int GetHTFBias(string symbol, ENUM_TIMEFRAMES htf, datetime currentTime)
{
    double pointSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double pipsMultiplier = (pointSize == 0.001 || pointSize == 0.00001) ? 10.0 : 1.0;

    int shift = iBarShift(symbol, htf, currentTime);
    if(shift < 0) return 0; 

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, htf, shift + 1, 80, rates);
    if(copied < 5) return 0;

    for(int i = 0; i < copied - 1; i++)
    {
        double prevOpen = rates[i+1].open, prevHigh = rates[i+1].high, prevLow = rates[i+1].low, prevClose = rates[i+1].close;
        double currOpen = rates[i].open, currHigh = rates[i].high, currLow = rates[i].low, currClose = rates[i].close;

        double prevRangeBase = prevHigh - prevLow;
        if((prevRangeBase / (pointSize * pipsMultiplier)) < InpMinRangePips) continue;

        int bias = 0;
        double sl = 0, tp = 0;

        if(currLow < prevLow && currClose > prevLow && currClose < prevHigh) { // Bull Sweep (TP 100%)
            bias = 1; sl = currLow; tp = prevHigh;
        }
        else if(currHigh > prevHigh && currClose < prevHigh && currClose > prevLow) { // Bear Sweep (TP 100%)
            bias = -1; sl = currHigh; tp = prevLow;
        }
        else if(currHigh > prevHigh && currClose > prevHigh) { // Bull Run
            bias = 1; sl = currLow; tp = MathMax(prevHigh + (prevRangeBase * 0.618), currHigh);
        }
        else if(currLow < prevLow && currClose < prevLow) { // Bear Run
            bias = -1; sl = currHigh; tp = MathMin(prevLow - (prevRangeBase * 0.618), currLow);
        }

        if(bias != 0) {
            bool isAlive = true;
            for(int j = i - 1; j >= 0; j--) {
                if(bias == 1) { 
                    if(rates[j].low <= sl || rates[j].high >= tp) { isAlive = false; break; }
                } else { 
                    if(rates[j].high >= sl || rates[j].low <= tp) { isAlive = false; break; }
                }
            }
            if(isAlive) return bias;
            else return 0; 
        }
    }
    return 0;
}

void AnalyzeAlignedTimeframe(ENUM_TIMEFRAMES tf)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, tf, 0, 3000, rates);
    if(copied < 10) return;

    // Arrays para D1
    int d1_alW1[4][3]; ArrayInitialize(d1_alW1, 0);
    int d1_agW1[4][3]; ArrayInitialize(d1_agW1, 0);
    int d1_ntW1[4][3]; ArrayInitialize(d1_ntW1, 0);

    // Arrays para LTFs (Las 9 permutaciones posibles)
    int ltf_D1yes_W1yes[4][3]; ArrayInitialize(ltf_D1yes_W1yes, 0);
    int ltf_D1yes_W1no[4][3];  ArrayInitialize(ltf_D1yes_W1no, 0);
    int ltf_D1yes_W1nt[4][3];  ArrayInitialize(ltf_D1yes_W1nt, 0);
    
    int ltf_D1no_W1yes[4][3];  ArrayInitialize(ltf_D1no_W1yes, 0);
    int ltf_D1nt_W1yes[4][3];  ArrayInitialize(ltf_D1nt_W1yes, 0);
    
    int ltf_D1no_W1no[4][3];   ArrayInitialize(ltf_D1no_W1no, 0);
    int ltf_D1no_W1nt[4][3];   ArrayInitialize(ltf_D1no_W1nt, 0);
    int ltf_D1nt_W1no[4][3];   ArrayInitialize(ltf_D1nt_W1no, 0);
    int ltf_D1nt_W1nt[4][3];   ArrayInitialize(ltf_D1nt_W1nt, 0);

    double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double pipsMultiplier = (pointSize == 0.001 || pointSize == 0.00001) ? 10.0 : 1.0;

    for(int i = copied - 2; i >= 2; i--) 
    {
        datetime time = rates[i].time;
        int biasW1 = GetHTFBias(_Symbol, PERIOD_W1, time);
        int biasD1 = (tf < PERIOD_D1) ? GetHTFBias(_Symbol, PERIOD_D1, time) : 0;

        double prevOpen = rates[i+1].open, prevHigh = rates[i+1].high, prevLow = rates[i+1].low, prevClose = rates[i+1].close;
        double prevRangeBase = prevHigh - prevLow;
        if((prevRangeBase / (pointSize * pipsMultiplier)) < InpMinRangePips) continue;

        double currOpen = rates[i].open, currHigh = rates[i].high, currLow = rates[i].low, currClose = rates[i].close;
        double prevRangeMid = prevLow + (prevRangeBase * 0.5);

        int res = 0; int dir = 0; int patIdx = -1;

        if(currLow < prevLow && currClose > prevLow && currClose < prevHigh) {
            dir = 1; patIdx = 0; res = Simulate(rates, i-1, dir, currLow, prevRangeMid);
        } else if(currHigh > prevHigh && currClose < prevHigh && currClose > prevLow) {
            dir = -1; patIdx = 1; res = Simulate(rates, i-1, dir, currHigh, prevRangeMid);
        } else if(currHigh > prevHigh && currClose > prevHigh) {
            dir = 1; patIdx = 2; res = Simulate(rates, i-1, dir, currLow, MathMax(prevHigh + (prevRangeBase * 0.618), currHigh));
        } else if(currLow < prevLow && currClose < prevLow) {
            dir = -1; patIdx = 3; res = Simulate(rates, i-1, dir, currHigh, MathMin(prevLow - (prevRangeBase * 0.618), currLow));
        }

        if(res != 0 && patIdx != -1) {
            if(tf == PERIOD_D1) {
                if(dir == biasW1)      { d1_alW1[patIdx][0]++; if(res==1) d1_alW1[patIdx][1]++; else d1_alW1[patIdx][2]++; }
                else if(biasW1 == -dir){ d1_agW1[patIdx][0]++; if(res==1) d1_agW1[patIdx][1]++; else d1_agW1[patIdx][2]++; }
                else                   { d1_ntW1[patIdx][0]++; if(res==1) d1_ntW1[patIdx][1]++; else d1_ntW1[patIdx][2]++; }
            } else {
                // Las 9 permutaciones para LTF
                if(dir == biasD1 && dir == biasW1)           { ltf_D1yes_W1yes[patIdx][0]++; if(res==1) ltf_D1yes_W1yes[patIdx][1]++; else ltf_D1yes_W1yes[patIdx][2]++; }
                else if(dir == biasD1 && biasW1 == -dir)     { ltf_D1yes_W1no[patIdx][0]++;  if(res==1) ltf_D1yes_W1no[patIdx][1]++;  else ltf_D1yes_W1no[patIdx][2]++; }
                else if(dir == biasD1 && biasW1 == 0)        { ltf_D1yes_W1nt[patIdx][0]++;  if(res==1) ltf_D1yes_W1nt[patIdx][1]++;  else ltf_D1yes_W1nt[patIdx][2]++; }
                
                else if(biasD1 == -dir && dir == biasW1)     { ltf_D1no_W1yes[patIdx][0]++;  if(res==1) ltf_D1no_W1yes[patIdx][1]++;  else ltf_D1no_W1yes[patIdx][2]++; }
                else if(biasD1 == 0 && dir == biasW1)        { ltf_D1nt_W1yes[patIdx][0]++;  if(res==1) ltf_D1nt_W1yes[patIdx][1]++;  else ltf_D1nt_W1yes[patIdx][2]++; }
                
                else if(biasD1 == -dir && biasW1 == -dir)    { ltf_D1no_W1no[patIdx][0]++;   if(res==1) ltf_D1no_W1no[patIdx][1]++;   else ltf_D1no_W1no[patIdx][2]++; }
                else if(biasD1 == -dir && biasW1 == 0)       { ltf_D1no_W1nt[patIdx][0]++;   if(res==1) ltf_D1no_W1nt[patIdx][1]++;   else ltf_D1no_W1nt[patIdx][2]++; }
                else if(biasD1 == 0 && biasW1 == -dir)       { ltf_D1nt_W1no[patIdx][0]++;   if(res==1) ltf_D1nt_W1no[patIdx][1]++;   else ltf_D1nt_W1no[patIdx][2]++; }
                else if(biasD1 == 0 && biasW1 == 0)          { ltf_D1nt_W1nt[patIdx][0]++;   if(res==1) ltf_D1nt_W1nt[patIdx][1]++;   else ltf_D1nt_W1nt[patIdx][2]++; }
            }
        }
    }
    
    // Impresión de Resultados
    if(tf == PERIOD_D1) {
        Print("================= D1 vs W1 =================");
        Print("✅ D1 ALINEADO con W1");      PrintResults(d1_alW1);
        Print("❌ D1 EN CONTRA de W1");      PrintResults(d1_agW1);
        Print("⚖️ W1 NEUTRAL");              PrintResults(d1_ntW1);
    } else {
        Print("============= LTF vs D1 & W1 ===============");
        Print("🥇 ALINEACIÓN TOTAL (A favor D1 y W1)");     PrintResults(ltf_D1yes_W1yes);
        Print("--------------------------------------------");
        Print("A favor D1, pero EN CONTRA de W1");          PrintResults(ltf_D1yes_W1no);
        Print("A favor D1, pero W1 Neutral");               PrintResults(ltf_D1yes_W1nt);
        Print("--------------------------------------------");
        Print("A favor W1, pero EN CONTRA de D1");          PrintResults(ltf_D1no_W1yes);
        Print("A favor W1, pero D1 Neutral");               PrintResults(ltf_D1nt_W1yes);
        Print("--------------------------------------------");
        Print("❌ EN CONTRA de Ambos (D1 y W1)");           PrintResults(ltf_D1no_W1no);
        Print("En contra D1, W1 Neutral");                  PrintResults(ltf_D1no_W1nt);
        Print("En contra W1, D1 Neutral");                  PrintResults(ltf_D1nt_W1no);
        Print("⚖️ AMBOS NEUTRALES (D1 y W1)");              PrintResults(ltf_D1nt_W1nt);
    }
}

int Simulate(MqlRates &rates[], int startIndex, int type, double sl, double tp) {
    for(int j = startIndex; j >= 0; j--) {
        if(type == 1) { 
            if(rates[j].low <= sl) return -1;
            if(rates[j].high >= tp) return 1;
        } else { 
            if(rates[j].high >= sl) return -1;
            if(rates[j].low <= tp) return 1;
        }
    }
    return 0;
}

void PrintResults(int &stats[][3]) {
    PrintFormat("🟢 BULL SWEEP | T: %3d | W: %3d | L: %3d | WR: %.1f%%", stats[0][0], stats[0][1], stats[0][2], (stats[0][0]>0 ? ((double)stats[0][1]/stats[0][0])*100 : 0));
    PrintFormat("🔴 BEAR SWEEP | T: %3d | W: %3d | L: %3d | WR: %.1f%%", stats[1][0], stats[1][1], stats[1][2], (stats[1][0]>0 ? ((double)stats[1][1]/stats[1][0])*100 : 0));
    PrintFormat("🚀 BULL RUN   | T: %3d | W: %3d | L: %3d | WR: %.1f%%", stats[2][0], stats[2][1], stats[2][2], (stats[2][0]>0 ? ((double)stats[2][1]/stats[2][0])*100 : 0));
    PrintFormat("☄️ BEAR RUN   | T: %3d | W: %3d | L: %3d | WR: %.1f%%", stats[3][0], stats[3][1], stats[3][2], (stats[3][0]>0 ? ((double)stats[3][1]/stats[3][0])*100 : 0));
}
//+------------------------------------------------------------------+
