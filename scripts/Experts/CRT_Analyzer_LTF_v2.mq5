//+------------------------------------------------------------------+
//|                                        CRT_Analyzer_M5_FVG.mq5   |
//|                                    Smart Money Concepts - V23.0  |
//|                 (Sweep W1/D1/London/Asia + FVG + Mitigación M5)  |
//+------------------------------------------------------------------+
#property copyright "SMC Algorithmic Trading"
#property link      ""
#property version   "23.00"
#property script_show_inputs

input int InpLookbackSweep = 20;  // Velas M5 hacia atrás para buscar el Sweep
input double InpMinFVGPips = 1.0; // Tamaño mínimo del FVG en pips

// Configuración de Sesiones (Horario del Broker - Ajustar según tu broker)
input int InpAsiaStartH   = 23;    // Inicio Asia (Ej. 01:00)
input int InpAsiaEndH     = 7;    // Fin Asia (Ej. 07:00)
input int InpLondonStartH = 9;    // Inicio Londres (Ej. 09:00)
input int InpLondonEndH   = 13;   // Fin Londres (Ej. 14:00)

void OnStart()
{
    Print("=====================================================================");
    Print(" INICIANDO MATRIX DE LIQUIDEZ TOTAL V23 (W1, D1, London, Asia) : ", _Symbol);
    Print("=====================================================================");

    AnalyzeM5Entries();
    
    Print("================= FIN DEL ANÁLISIS V23 ==================");
}

void GetSessionHL(datetime currentTime, int startHour, int endHour, double &high, double &low) 
{
    high = -1; low = -1;
    datetime dayStart = currentTime - (currentTime % 86400); // 00:00 del día actual
    datetime sessionStart = dayStart + startHour * 3600;
    datetime sessionEnd = dayStart + endHour * 3600;

    // Solo validamos la liquidez de la sesión si la sesión ya ha terminado
    if (currentTime <= sessionEnd) return; 

    int startIdx = iBarShift(_Symbol, PERIOD_M5, sessionEnd);
    int endIdx = iBarShift(_Symbol, PERIOD_M5, sessionStart);
    
    if(startIdx < 0 || endIdx < 0) return;
    int count = endIdx - startIdx + 1;
    if(count <= 0) return;

    int highestIdx = iHighest(_Symbol, PERIOD_M5, MODE_HIGH, count, startIdx);
    int lowestIdx  = iLowest(_Symbol, PERIOD_M5, MODE_LOW, count, startIdx);

    if(highestIdx >= 0) high = iHigh(_Symbol, PERIOD_M5, highestIdx);
    if(lowestIdx >= 0)  low = iLow(_Symbol, PERIOD_M5, lowestIdx);
}

void AnalyzeM5Entries()
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, PERIOD_M5, 0, 120000, rates); // Aprox 2.5 meses en M5
    if(copied < 100) return;

    // Stats = {Total, 1:1, 1:2, 1:3, SL}
    int bull_W1[5]={0}, bull_D1[5]={0}, bull_Lon[5]={0}, bull_Asi[5]={0};
    int bear_W1[5]={0}, bear_D1[5]={0}, bear_Lon[5]={0}, bear_Asi[5]={0};

    double pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double pipsMult = (pointSize == 0.001 || pointSize == 0.00001) ? 10.0 : 1.0;

    for(int i = copied - 5; i >= 1; i--) 
    {
        datetime time = rates[i].time;
        
        // --- 1. Obtener Niveles de Liquidez (W1 y D1) ---
        int w1_shift = iBarShift(_Symbol, PERIOD_W1, time);
        int d1_shift = iBarShift(_Symbol, PERIOD_D1, time);
        
        double pwh = (w1_shift >= 0) ? iHigh(_Symbol, PERIOD_W1, w1_shift + 1) : 999999;
        double pwl = (w1_shift >= 0) ? iLow(_Symbol, PERIOD_W1, w1_shift + 1) : -1;
        double pdh = (d1_shift >= 0) ? iHigh(_Symbol, PERIOD_D1, d1_shift + 1) : 999999;
        double pdl = (d1_shift >= 0) ? iLow(_Symbol, PERIOD_D1, d1_shift + 1) : -1;

        // --- 2. Obtener Niveles de Sesión ---
        double asiaH = -1, asiaL = -1, lonH = -1, lonL = -1;
        GetSessionHL(time, InpAsiaStartH, InpAsiaEndH, asiaH, asiaL);
        GetSessionHL(time, InpLondonStartH, InpLondonEndH, lonH, lonL);
        
        if(asiaH == -1) asiaH = 999999; if(lonH == -1) lonH = 999999;

        // --- 3. Detección del FVG en M5 ---
        double c1_high = rates[i+2].high, c1_low = rates[i+2].low;
        double c3_high = rates[i].high,   c3_low = rates[i].low;

        // 🟢 BULLISH FVG (Posible compra)
        if(c3_low > c1_high && ((c3_low - c1_high) / (pointSize * pipsMult)) >= InpMinFVGPips) 
        {
            double lowestLow = rates[i].low;
            for(int k = i; k <= i + InpLookbackSweep && k < copied; k++) {
                if(rates[k].low < lowestLow) lowestLow = rates[k].low;
            }

            int poolSwept = 0; // 1=W1, 2=D1, 3=London, 4=Asia
            if(pwl != -1 && lowestLow < pwl) poolSwept = 1;
            else if(pdl != -1 && lowestLow < pdl) poolSwept = 2;
            else if(lonL != -1 && lowestLow < lonL) poolSwept = 3;
            else if(asiaL != -1 && lowestLow < asiaL) poolSwept = 4;

            if(poolSwept > 0) {
                int res = ExecuteMitigation(rates, i, 1, c1_high, lowestLow);
                if(res != 0) {
                    if(poolSwept == 1)      { bull_W1[0]++;  if(res>=1) bull_W1[1]++;  if(res>=2) bull_W1[2]++;  if(res==3) bull_W1[3]++;  if(res==-1) bull_W1[4]++; }
                    else if(poolSwept == 2) { bull_D1[0]++;  if(res>=1) bull_D1[1]++;  if(res>=2) bull_D1[2]++;  if(res==3) bull_D1[3]++;  if(res==-1) bull_D1[4]++; }
                    else if(poolSwept == 3) { bull_Lon[0]++; if(res>=1) bull_Lon[1]++; if(res>=2) bull_Lon[2]++; if(res==3) bull_Lon[3]++; if(res==-1) bull_Lon[4]++; }
                    else if(poolSwept == 4) { bull_Asi[0]++; if(res>=1) bull_Asi[1]++; if(res>=2) bull_Asi[2]++; if(res==3) bull_Asi[3]++; if(res==-1) bull_Asi[4]++; }
                }
            }
        }

        // 🔴 BEARISH FVG (Posible venta)
        else if(c3_high < c1_low && ((c1_low - c3_high) / (pointSize * pipsMult)) >= InpMinFVGPips) 
        {
            double highestHigh = rates[i].high;
            for(int k = i; k <= i + InpLookbackSweep && k < copied; k++) {
                if(rates[k].high > highestHigh) highestHigh = rates[k].high;
            }

            int poolSwept = 0; // 1=W1, 2=D1, 3=London, 4=Asia
            if(pwh != 999999 && highestHigh > pwh) poolSwept = 1;
            else if(pdh != 999999 && highestHigh > pdh) poolSwept = 2;
            else if(lonH != 999999 && highestHigh > lonH) poolSwept = 3;
            else if(asiaH != 999999 && highestHigh > asiaH) poolSwept = 4;

            if(poolSwept > 0) {
                int res = ExecuteMitigation(rates, i, -1, c1_low, highestHigh);
                if(res != 0) {
                    if(poolSwept == 1)      { bear_W1[0]++;  if(res>=1) bear_W1[1]++;  if(res>=2) bear_W1[2]++;  if(res==3) bear_W1[3]++;  if(res==-1) bear_W1[4]++; }
                    else if(poolSwept == 2) { bear_D1[0]++;  if(res>=1) bear_D1[1]++;  if(res>=2) bear_D1[2]++;  if(res==3) bear_D1[3]++;  if(res==-1) bear_D1[4]++; }
                    else if(poolSwept == 3) { bear_Lon[0]++; if(res>=1) bear_Lon[1]++; if(res>=2) bear_Lon[2]++; if(res==3) bear_Lon[3]++; if(res==-1) bear_Lon[4]++; }
                    else if(poolSwept == 4) { bear_Asi[0]++; if(res>=1) bear_Asi[1]++; if(res>=2) bear_Asi[2]++; if(res==3) bear_Asi[3]++; if(res==-1) bear_Asi[4]++; }
                }
            }
        }
    }

    Print("============== 🟢 COMPRAS EN M5 (BULLISH FVG) ==============");
    PrintResults("1. Sweep de SEMANAL (PWL)", bull_W1);
    PrintResults("2. Sweep de DIARIO  (PDL)", bull_D1);
    PrintResults("3. Sweep de LONDRES (LonL)", bull_Lon);
    PrintResults("4. Sweep de ASIA    (AsiL)", bull_Asi);

    Print("============== 🔴 VENTAS EN M5 (BEARISH FVG) ==============");
    PrintResults("1. Sweep de SEMANAL (PWH)", bear_W1);
    PrintResults("2. Sweep de DIARIO  (PDH)", bear_D1);
    PrintResults("3. Sweep de LONDRES (LonH)", bear_Lon);
    PrintResults("4. Sweep de ASIA    (AsiH)", bear_Asi);
}

// Simulador: Espera mitigación, luego calcula TPs
int ExecuteMitigation(MqlRates &rates[], int fvgIndex, int dir, double entry, double sl)
{
    double risk = MathAbs(entry - sl);
    if(risk <= 0) return 0;

    double tp1 = (dir == 1) ? entry + risk : entry - risk;
    double tp2 = (dir == 1) ? entry + (risk * 2) : entry - (risk * 2);
    double tp3 = (dir == 1) ? entry + (risk * 3) : entry - (risk * 3);

    bool isMitigated = false;
    int mitigateIndex = -1;

    // 1. Esperar a que el precio toque el FVG
    for(int m = fvgIndex - 1; m >= 0; m--) {
        if(dir == 1) { // Compra
            if(rates[m].low <= entry) { isMitigated = true; mitigateIndex = m; break; }
            if(rates[m].high > entry + (risk * 3)) return 0; // Se fue sin mitigar, se anula
        } else { // Venta
            if(rates[m].high >= entry) { isMitigated = true; mitigateIndex = m; break; }
            if(rates[m].low < entry - (risk * 3)) return 0; // Se fue sin mitigar, se anula
        }
    }

    if(!isMitigated) return 0;

    // 2. Una vez dentro de la operación, simular TPs vs SL
    int highestHit = 0;
    for(int j = mitigateIndex; j >= 0; j--) {
        if(dir == 1) {
            if(rates[j].low <= sl) return (highestHit > 0) ? highestHit : -1;
            if(rates[j].high >= tp3) return 3;
            if(rates[j].high >= tp2 && highestHit < 2) highestHit = 2;
            if(rates[j].high >= tp1 && highestHit < 1) highestHit = 1;
        } else {
            if(rates[j].high >= sl) return (highestHit > 0) ? highestHit : -1;
            if(rates[j].low <= tp3) return 3;
            if(rates[j].low <= tp2 && highestHit < 2) highestHit = 2;
            if(rates[j].low <= tp1 && highestHit < 1) highestHit = 1;
        }
    }
    return highestHit;
}

void PrintResults(string title, int &stats[]) {
    int total = stats[0];
    if(total == 0) { Print(title, " -> 0 Patrones encontrados."); return; }
    
    double loss = ((double)stats[4] / total) * 100.0;
    double wr1  = ((double)stats[1] / total) * 100.0;
    double wr2  = ((double)stats[2] / total) * 100.0;
    double wr3  = ((double)stats[3] / total) * 100.0;

    Print(title, " | Total: ", total);
    PrintFormat("   💥 Toca SL      : %.1f%%", loss);
    PrintFormat("   🎯 Ratio 1:1    : %.1f%%", wr1);
    PrintFormat("   🚀 Ratio 1:2    : %.1f%%", wr2);
    PrintFormat("   🔥 Ratio 1:3    : %.1f%%", wr3);
    Print("------------------------------------------------------");
}
//+------------------------------------------------------------------+