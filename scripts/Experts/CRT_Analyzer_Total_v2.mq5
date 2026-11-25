//+------------------------------------------------------------------+
//|                                           CRT_Analyzer_Total.mq5 |
//|                                    Smart Money Concepts - V15.0  |
//|                                 (A/B Testing: Comparador de V0-V4)|
//+------------------------------------------------------------------+
#property copyright "SMC Algorithmic Trading"
#property link      ""
#property version   "15.00"
#property script_show_inputs

input double InpMinRangePips = 5.0; // Rango mínimo vela anterior en Pips
input double InpWickRatio    = 1.5; // Filtro 1: Ratio Mecha vs Cuerpo

void OnStart()
{
    Print("=====================================================================");
    Print(" INICIANDO ANALIZADOR MAESTRO V15 (A/B Testing de Filtros) : ", _Symbol);
    Print("=====================================================================");

    ENUM_TIMEFRAMES timeframes[] = {PERIOD_W1, PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H4};
    int totalTimeframes = ArraySize(timeframes);

    for(int tf = 0; tf < totalTimeframes; tf++)
    {
        Print("--- TIMEFRAME: ", EnumToString(timeframes[tf]), " ---");
        AnalyzeTimeframe(timeframes[tf]);
        Print("---------------------------------------");
    }
    Print("================= FIN DEL COMPARADOR V15 ==================");
}

void AnalyzeTimeframe(ENUM_TIMEFRAMES tf)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, tf, 0, 1000, rates);
    if(copied < 10) return;

    // Arrays para guardar [Total, Wins, Losses] de cada versión (0 a 4)
    int bullStats[5][3]; ArrayInitialize(bullStats, 0);
    int bearStats[5][3]; ArrayInitialize(bearStats, 0);

    double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double pipsMultiplier = (pointSize == 0.001 || pointSize == 0.00001) ? 10.0 : 1.0;

    for(int i = copied - 2; i >= 2; i--) 
    {
        double prevOpen = rates[i+1].open, prevHigh = rates[i+1].high, prevLow = rates[i+1].low, prevClose = rates[i+1].close;
        double prevRangeBase = prevHigh - prevLow;
        if((prevRangeBase / (pointSize * pipsMultiplier)) < InpMinRangePips) continue;

        double currOpen = rates[i].open, currHigh = rates[i].high, currLow = rates[i].low, currClose = rates[i].close;
        
        double bodySize     = MathAbs(currClose - currOpen);
        double lowerWick    = MathMin(currOpen, currClose) - currLow;
        double upperWick    = currHigh - MathMax(currOpen, currClose);
        double prevRangeMid = prevLow + (prevRangeBase * 0.5);
        
        bool isPrevBear = prevClose < prevOpen, isPrevBull = prevClose > prevOpen;
        bool isCurrBull = currClose > currOpen, isCurrBear = currClose < currOpen;

        //===================================================================
        // 1. BULL SWEEP (Compra)
        //===================================================================
        if(currLow < prevLow && currClose > prevLow && currClose < prevHigh)
        {
            bool condRatio = (lowerWick >= (bodySize * InpWickRatio));
            bool condProx  = (currClose <= prevRangeMid);
            bool condColor = (isPrevBear && isCurrBull);

            double slPrice = currLow;
            double tpPrice = prevRangeMid;
            int result = 0; // 0=Pendiente, 1=Win, -1=Loss

            // Simular futuro para ver si es Win o Loss
            for(int j = i - 1; j >= 0; j--) {
                if(rates[j].low <= slPrice) { result = -1; break; }
                if(rates[j].high >= tpPrice) { result = 1; break; }
            }

            if(result != 0) {
                // V0: Original (Entran todos)
                bullStats[0][0]++; if(result==1) bullStats[0][1]++; else bullStats[0][2]++;
                
                // V1: Solo Ratio
                if(condRatio) { bullStats[1][0]++; if(result==1) bullStats[1][1]++; else bullStats[1][2]++; }
                
                // V2: Solo Proximidad
                if(condProx) { bullStats[2][0]++; if(result==1) bullStats[2][1]++; else bullStats[2][2]++; }
                
                // V3: Solo Color
                if(condColor) { bullStats[3][0]++; if(result==1) bullStats[3][1]++; else bullStats[3][2]++; }
                
                // V4: Combo Perfecto
                if(condRatio && condProx && condColor) { bullStats[4][0]++; if(result==1) bullStats[4][1]++; else bullStats[4][2]++; }
            }
        }

        //===================================================================
        // 2. BEAR SWEEP (Venta)
        //===================================================================
        if(currHigh > prevHigh && currClose < prevHigh && currClose > prevLow)
        {
            bool condRatio = (upperWick >= (bodySize * InpWickRatio));
            bool condProx  = (currClose >= prevRangeMid);
            bool condColor = (isPrevBull && isCurrBear);

            double slPrice = currHigh;
            double tpPrice = prevRangeMid;
            int result = 0; // 0=Pendiente, 1=Win, -1=Loss

            // Simular futuro
            for(int j = i - 1; j >= 0; j--) {
                if(rates[j].high >= slPrice) { result = -1; break; }
                if(rates[j].low <= tpPrice) { result = 1; break; }
            }

            if(result != 0) {
                // V0: Original
                bearStats[0][0]++; if(result==1) bearStats[0][1]++; else bearStats[0][2]++;
                
                // V1: Solo Ratio
                if(condRatio) { bearStats[1][0]++; if(result==1) bearStats[1][1]++; else bearStats[1][2]++; }
                
                // V2: Solo Proximidad
                if(condProx) { bearStats[2][0]++; if(result==1) bearStats[2][1]++; else bearStats[2][2]++; }
                
                // V3: Solo Color
                if(condColor) { bearStats[3][0]++; if(result==1) bearStats[3][1]++; else bearStats[3][2]++; }
                
                // V4: Combo Perfecto
                if(condRatio && condProx && condColor) { bearStats[4][0]++; if(result==1) bearStats[4][1]++; else bearStats[4][2]++; }
            }
        }
    }
    
    // Función local para imprimir bonito
    Print("🟢 BULL SWEEPS (Compras):");
    PrintFormat("   V0 (Original)   | T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bullStats[0][0], bullStats[0][1], bullStats[0][2], (bullStats[0][0]>0 ? ((double)bullStats[0][1]/bullStats[0][0])*100 : 0));
    PrintFormat("   V1 (Ratio Mecha)| T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bullStats[1][0], bullStats[1][1], bullStats[1][2], (bullStats[1][0]>0 ? ((double)bullStats[1][1]/bullStats[1][0])*100 : 0));
    PrintFormat("   V2 (Cierre 50%) | T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bullStats[2][0], bullStats[2][1], bullStats[2][2], (bullStats[2][0]>0 ? ((double)bullStats[2][1]/bullStats[2][0])*100 : 0));
    PrintFormat("   V3 (Color)      | T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bullStats[3][0], bullStats[3][1], bullStats[3][2], (bullStats[3][0]>0 ? ((double)bullStats[3][1]/bullStats[3][0])*100 : 0));
    PrintFormat("   V4 (Perfectos)  | T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bullStats[4][0], bullStats[4][1], bullStats[4][2], (bullStats[4][0]>0 ? ((double)bullStats[4][1]/bullStats[4][0])*100 : 0));

    Print("🔴 BEAR SWEEPS (Ventas):");
    PrintFormat("   V0 (Original)   | T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bearStats[0][0], bearStats[0][1], bearStats[0][2], (bearStats[0][0]>0 ? ((double)bearStats[0][1]/bearStats[0][0])*100 : 0));
    PrintFormat("   V1 (Ratio Mecha)| T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bearStats[1][0], bearStats[1][1], bearStats[1][2], (bearStats[1][0]>0 ? ((double)bearStats[1][1]/bearStats[1][0])*100 : 0));
    PrintFormat("   V2 (Cierre 50%) | T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bearStats[2][0], bearStats[2][1], bearStats[2][2], (bearStats[2][0]>0 ? ((double)bearStats[2][1]/bearStats[2][0])*100 : 0));
    PrintFormat("   V3 (Color)      | T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bearStats[3][0], bearStats[3][1], bearStats[3][2], (bearStats[3][0]>0 ? ((double)bearStats[3][1]/bearStats[3][0])*100 : 0));
    PrintFormat("   V4 (Perfectos)  | T: %3d | W: %3d | L: %3d | WinRate: %.1f%%", bearStats[4][0], bearStats[4][1], bearStats[4][2], (bearStats[4][0]>0 ? ((double)bearStats[4][1]/bearStats[4][0])*100 : 0));
}