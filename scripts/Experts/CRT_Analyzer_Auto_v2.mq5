//+------------------------------------------------------------------+
//|                                     SMC_Universal_Bot_v1.2.mq5   |
//|             Trader Cuantitativo SMC - Reingreso Fractal (V1.2)   |
//+------------------------------------------------------------------+
#property copyright "SMC Quant Fund"
#property version   "1.20"

#include <Trade\Trade.mqh>

//--- INPUTS
sinput string  _cfg_      = "--- CONFIGURACIÓN GENERAL ---";
input double   InpRiskPct = 1.0;            // Riesgo por Trade (%)
input ulong    InpMagic   = 123456;         // Magic Number
input double InpMinPips = 5.0; // Rango Mínimo Vela MTF (Pips)

sinput string  _tf_       = "--- TIMEFRAMES DESACOPLADOS ---";
input ENUM_TIMEFRAMES InpMTF = PERIOD_H4;   // Contexto y Estructura (MTF)
input ENUM_TIMEFRAMES InpLTF = PERIOD_M15;  // Gatillo de Ejecución (LTF)

sinput string  _mod_      = "--- MÓDULOS ACTIVOS ---";
input bool     InpUseRuns   = true;         // Operar Expansiones (Runs)
input int      InpRunScore  = 3;            // Min Bias Score para Runs (+3 o -3)
input bool     InpUseSweeps = true;         // Operar Anticipación (Sweeps con Reingreso)
input int      InpSweepScore = 1;           // Max Bias Score para Sweeps (Fricción)

//--- GLOBALES
CTrade trade;
datetime lastLTFCandle = 0;

//+------------------------------------------------------------------+
//| Inicialización
//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(InpMagic);
    Print("🚀 SMC Universal Bot V1.2 (Reingreso Fractal) Inicializado en ", _Symbol);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Motor Principal (Se ejecuta con cada Tick, evalúa al cierre LTF)
//+------------------------------------------------------------------+
void OnTick() {
    // Evitamos operar si ya tenemos una posición abierta en este par
    if(PositionsTotal() > 0) {
        for(int i=0; i<PositionsTotal(); i++) {
            if(PositionGetSymbol(i) == _Symbol) return; 
        }
    }

    datetime currentLTF = iTime(_Symbol, InpLTF, 0);
    // Solo evaluamos en el milisegundo exacto en que cierra la vela LTF (M15)
    if(currentLTF != lastLTFCandle) {
        lastLTFCandle = currentLTF;
        
        int biasW1 = GetHTFBias(PERIOD_W1, TimeCurrent());
        int biasD1 = GetHTFBias(PERIOD_D1, TimeCurrent());
        
        int scoreBull = (biasW1 == 1 ? 2 : (biasW1 == -1 ? -2 : 0)) + (biasD1 == 1 ? 1 : (biasD1 == -1 ? -1 : 0));
        int scoreBear = (biasW1 == -1 ? 2 : (biasW1 == 1 ? -2 : 0)) + (biasD1 == -1 ? 1 : (biasD1 == 1 ? -1 : 0));

        if(InpUseSweeps) CheckAnticipatedSweeps(scoreBull, scoreBear);
        if(InpUseRuns)   CheckRunPullbacks(scoreBull, scoreBear);
    }
}

//+------------------------------------------------------------------+
//| MÓDULO 1: ANTICIPACIÓN DE SWEEPS (Con Condición de Reingreso)
//+------------------------------------------------------------------+
void CheckAnticipatedSweeps(int scoreBull, int scoreBear) {
    MqlRates mtf[], ltf[];
    ArraySetAsSeries(mtf, true); ArraySetAsSeries(ltf, true);
    
    if(CopyRates(_Symbol, InpMTF, 0, 3, mtf) < 3) return; // 0=Formándose, 1=Anterior
    if(CopyRates(_Symbol, InpLTF, 1, 3, ltf) < 3) return; // 1=Recién Cerrada, 2=Anterior

    double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // Niveles HTF
    int wIdx = iBarShift(_Symbol, PERIOD_W1, TimeCurrent()) + 1;
    double pwh = (wIdx > 0) ? iHigh(_Symbol, PERIOD_W1, wIdx) : 0;
    double pwl = (wIdx > 0) ? iLow(_Symbol, PERIOD_W1, wIdx) : 999999;
    
    int dIdx = iBarShift(_Symbol, PERIOD_D1, TimeCurrent()) + 1;
    double pdh = (dIdx > 0) ? iHigh(_Symbol, PERIOD_D1, dIdx) : 0;
    double pdl = (dIdx > 0) ? iLow(_Symbol, PERIOD_D1, dIdx) : 999999;

    // --- REINGRESO FRACTAL BAJISTA (Bear Sweep) ---
    // 1. H4 hizo un alto más alto que la vela H4 anterior
    // 2. Pero el precio actual ya ha caído por debajo del alto de la vela H4 anterior (está dejando mecha)
    bool bearReEntry = (mtf[0].high > mtf[1].high) && (currentBid < mtf[1].high);
    
    // Gatillo LTF: M15 sube por encima de M15 anterior y cierra rojo
    bool ltfBearTrigger = (ltf[1].high > ltf[2].high) && (ltf[1].close < ltf[1].open);
    
    // Zona de liquidez
    bool inBearZone = (ltf[1].high > pdh || ltf[1].high > pwh);

    if(bearReEntry && ltfBearTrigger && inBearZone && scoreBear <= InpSweepScore && scoreBear > -3) {
        double sl = ltf[1].high; // Punta de la mecha de M15
        double tp = mtf[1].low + ((mtf[1].high - mtf[1].low) * 0.5); // 50% de la vela H4 anterior
        
        ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Bear Sweep Anticipado (Reingreso)");
        return;
    }

    // --- REINGRESO FRACTAL ALCISTA (Bull Sweep) ---
    // 1. H4 hizo un bajo más bajo que la vela H4 anterior
    // 2. Pero el precio actual ya subió por encima del mínimo de la vela H4 anterior
    bool bullReEntry = (mtf[0].low < mtf[1].low) && (currentAsk > mtf[1].low);
    
    // Gatillo LTF: M15 cae por debajo de M15 anterior y cierra verde
    bool ltfBullTrigger = (ltf[1].low < ltf[2].low) && (ltf[1].close > ltf[1].open);
    
    // Zona de liquidez
    bool inBullZone = (ltf[1].low < pdl || ltf[1].low < pwl);

    if(bullReEntry && ltfBullTrigger && inBullZone && scoreBull <= InpSweepScore && scoreBull > -3) {
        double sl = ltf[1].low; // Punta de la mecha de M15
        double tp = mtf[1].low + ((mtf[1].high - mtf[1].low) * 0.5); // 50% de la vela H4 anterior
        
        ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Bull Sweep Anticipado (Reingreso)");
        return;
    }
}

//+------------------------------------------------------------------+
//| MÓDULO 2: PULLBACKS DE RUNS (Expansión Confirmada)
//+------------------------------------------------------------------+
void CheckRunPullbacks(int scoreBull, int scoreBear) {
    MqlRates mtf[], ltf[];
    ArraySetAsSeries(mtf, true); ArraySetAsSeries(ltf, true);
    
    if(CopyRates(_Symbol, InpMTF, 1, 3, mtf) < 3) return; // 1=Última H4 cerrada, 2=Anterior a esa
    if(CopyRates(_Symbol, InpLTF, 1, 3, ltf) < 3) return; // 1=Recién Cerrada M15, 2=Anterior

    double pS = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double pM = (pS == 0.001 || pS == 0.00001) ? 10.0 : 1.0;
    double range = mtf[2].high - mtf[2].low;
    if((range / (pS * pM)) < InpMinPips) return;

    // ¿La última vela H4 cerrada fue un Run?
    bool isBullRunMTF = (mtf[1].open <= mtf[2].high && mtf[1].close > mtf[2].high);
    bool isBearRunMTF = (mtf[1].open >= mtf[2].low && mtf[1].close < mtf[2].low);

    // Gatillos LTF (Retrocesos)
    bool ltfBullPullback = (ltf[1].low < ltf[2].low) && (ltf[1].close > ltf[1].open);
    bool ltfBearPullback = (ltf[1].high > ltf[2].high) && (ltf[1].close < ltf[1].open);

    if(isBullRunMTF && ltfBullPullback && scoreBull >= InpRunScore) {
        double sl = mtf[1].low; // SL estructural H4 (Invalidación del Run)
        double tp = mtf[1].high + (range * 1.618); // Extensión del Run
        ExecuteTrade(ORDER_TYPE_BUY, sl, tp, "Bull Run Pullback");
        return;
    }

    if(isBearRunMTF && ltfBearPullback && scoreBear >= InpRunScore) {
        double sl = mtf[1].high; // SL estructural H4
        double tp = mtf[1].low - (range * 1.618);
        ExecuteTrade(ORDER_TYPE_SELL, sl, tp, "Bear Run Pullback");
        return;
    }
}

//+------------------------------------------------------------------+
//| Motor de Ejecución al Mercado
//+------------------------------------------------------------------+
void ExecuteTrade(ENUM_ORDER_TYPE type, double sl, double tp, string comment)
{
    double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double slDistance = MathAbs(price - sl);
    
    if(slDistance == 0) return;

    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    double riskAmount = accountBalance * (InpRiskPct / 100.0);
    double slPips = slDistance / tickSize;
    double lotSize = NormalizeDouble(riskAmount / (slPips * tickValue), 2);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;

    if(type == ORDER_TYPE_BUY) {
        trade.Buy(lotSize, _Symbol, price, sl, tp, comment);
        PrintFormat("📈 [%s] | Lotes: %.2f | SL: %.5f", comment, lotSize, sl);
    } else {
        trade.Sell(lotSize, _Symbol, price, sl, tp, comment);
        PrintFormat("📉 [%s] | Lotes: %.2f | SL: %.5f", comment, lotSize, sl);
    }
}

//+------------------------------------------------------------------+
//| Helper: Obtener Bias HTF
//+------------------------------------------------------------------+
int GetHTFBias(ENUM_TIMEFRAMES htf, datetime currentTime) {
    int shift = iBarShift(_Symbol, htf, currentTime);
    if(shift < 0) return 0; 
    
    MqlRates r[]; ArraySetAsSeries(r, true);
    if(CopyRates(_Symbol, htf, shift + 1, 60, r) < 5) return 0;

    double pS = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double pM = (pS == 0.001 || pS == 0.00001) ? 10.0 : 1.0;

    for(int i = 0; i < ArraySize(r) - 1; i++) {
        double pO=r[i+1].open, pH=r[i+1].high, pL=r[i+1].low;
        double cO=r[i].open, cH=r[i].high, cL=r[i].low, cC=r[i].close;
        if(((pH - pL) / (pS * pM)) < InpMinPips) continue;

        int b = 0; double sl = 0, tp = 0;
        if(cL < pL && cC > pL && cC < pH)      { b = 1; sl = cL; tp = pH; } 
        else if(cH > pH && cC < pH && cC > pL) { b = -1; sl = cH; tp = pL; } 
        else if(cO <= pH && cC > pH)           { b = 1; sl = cL; tp = MathMax(pH + ((pH-pL) * 0.618), cH); } 
        else if(cO >= pL && cC < pL)           { b = -1; sl = cH; tp = MathMin(pL - ((pH-pL) * 0.618), cL); } 

        if(b != 0) {
            bool alive = true;
            for(int j = i - 1; j >= 0; j--) {
                if(b == 1 && (r[j].low <= sl || r[j].high >= tp)) { alive = false; break; }
                if(b == -1 && (r[j].high >= sl || r[j].low <= tp)) { alive = false; break; }
            }
            return alive ? b : 0; 
        }
    }
    return 0;
}
//+------------------------------------------------------------------+