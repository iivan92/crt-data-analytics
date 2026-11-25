//+------------------------------------------------------------------+
//|                                     CRT_Analyzer_Auto_v4.mq5     |
//|                         Hybrid: V3 Liquidity + V4 PO3 + ATR      |
//+------------------------------------------------------------------+
#property copyright "SMC Algorithmic Trading"
#property version   "4.00"
#property strict

#include <Trade\Trade.mqh>

//--- PARÁMETROS DE ENTRADA
input ENUM_TIMEFRAMES InpHTF         = PERIOD_H4;      // Rango HTF (Vela Base)
input ENUM_TIMEFRAMES InpLTF         = PERIOD_M5;      // Temporalidad de Gatillo (Engulfing)
input int            InpLookback     = 15;             // Velas hacia atrás para detectar barridas
input int            InpAtrPeriod    = 14;             // Periodo ATR (Invalidación)
input double         InpAtrMultiplier= 2.0;            // Multiplicador ATR
input double         InpRiskPercent  = 0.5;            // Riesgo (%)

// Sesiones (Hora del Broker)
input string InpAsiaStart = "00:00";
input string InpAsiaEnd   = "06:00";
input string InpLonStart  = "07:00";
input string InpLonEnd    = "11:00";

//--- VARIABLES GLOBALES
CTrade trade;
int atrHandle;
double atrBuffer[];

double pointSize, pipsMult;
datetime currentDay = 0, currentWeek = 0;

// Niveles de Liquidez (Pools)
double PDH = EMPTY_VALUE, PDL = EMPTY_VALUE;
double PWH = EMPTY_VALUE, PWL = EMPTY_VALUE;
double AsiaH = EMPTY_VALUE, AsiaL = EMPTY_VALUE;
double LonH = EMPTY_VALUE, LonL = EMPTY_VALUE;

// Flags de Consumo
bool c_PDH=false, c_PDL=false, c_PWH=false, c_PWL=false;
bool c_AsiaH=false, c_AsiaL=false, c_LonH=false, c_LonL=false;

//+------------------------------------------------------------------+
//| Inicialización                                                   |
//+------------------------------------------------------------------+
int OnInit() {
    pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    pipsMult = (pointSize == 0.001 || pointSize == 0.00001) ? 10.0 : 1.0;
    
    atrHandle = iATR(_Symbol, PERIOD_CURRENT, InpAtrPeriod);
    ArraySetAsSeries(atrBuffer, true);
    
    Print("CRT Analyzer Auto V4 (Híbrido) Iniciado.");
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { 
    ObjectsDeleteAll(0, "CRT_");
    IndicatorRelease(atrHandle);
}

//+------------------------------------------------------------------+
//| Utilidades de Dibujo y Lotes                                     |
//+------------------------------------------------------------------+
void DrawLine(string name, double price, color clr) {
    if(price == EMPTY_VALUE || price == 0) return;
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(0, name, OBJPROP_BACK, true);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    } else {
        ObjectMove(0, name, 0, 0, price);
    }
}

void RemoveLine(string name) {
    ObjectDelete(0, name);
}

double CalculateLotSize(double entry, double sl) {
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmt = balance * (InpRiskPercent / 100.0);
    double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    double slDist = MathAbs(entry - sl);
    if(slDist <= 0) return 0.01;

    double lotSize = riskAmt / ((slDist / tickSize) * tickVal);
    
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    lotSize = MathFloor(lotSize / step) * step;
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    return lotSize;
}

//+------------------------------------------------------------------+
//| Refrescar Niveles de Liquidez (V3)                               |
//+------------------------------------------------------------------+
void RefreshHTFLevels() {
    datetime timeD1 = iTime(_Symbol, PERIOD_D1, 0);
    if(timeD1 != currentDay) {
        currentDay = timeD1;
        PDH = iHigh(_Symbol, PERIOD_D1, 1); 
        PDL = iLow(_Symbol, PERIOD_D1, 1);
        c_PDH = false; c_PDL = false;
        
        AsiaH = EMPTY_VALUE; AsiaL = EMPTY_VALUE; c_AsiaH = false; c_AsiaL = false;
        LonH = EMPTY_VALUE; LonL = EMPTY_VALUE; c_LonH = false; c_LonL = false;
        
        DrawLine("CRT_PDH", PDH, clrOrange);
        DrawLine("CRT_PDL", PDL, clrOrange);
    }

    datetime timeW1 = iTime(_Symbol, PERIOD_W1, 0);
    if(timeW1 != currentWeek) {
        currentWeek = timeW1;
        PWH = iHigh(_Symbol, PERIOD_W1, 1); 
        PWL = iLow(_Symbol, PERIOD_W1, 1);
        c_PWH = false; c_PWL = false;
        DrawLine("CRT_PWH", PWH, clrPurple);
        DrawLine("CRT_PWL", PWL, clrPurple);
    }

    // Calcular Asia y London extrayendo barras M1 del día actual
    if(AsiaH == EMPTY_VALUE || LonH == EMPTY_VALUE) {
        datetime todayStart = currentDay;
        string dtStr = TimeToString(todayStart, TIME_DATE);
        
        datetime a_start = StringToTime(dtStr + " " + InpAsiaStart);
        datetime a_end   = StringToTime(dtStr + " " + InpAsiaEnd);
        datetime l_start = StringToTime(dtStr + " " + InpLonStart);
        datetime l_end   = StringToTime(dtStr + " " + InpLonEnd);
        
        MqlRates m1[];
        int copied = CopyRates(_Symbol, PERIOD_M1, todayStart, TimeCurrent(), m1);
        
        double ah=0, al=999999, lh=0, ll=999999;
        bool foundAsia=false, foundLon=false;
        
        for(int i=0; i<copied; i++) {
            if(m1[i].time >= a_start && m1[i].time <= a_end) {
                if(m1[i].high > ah) ah = m1[i].high;
                if(m1[i].low < al)  al = m1[i].low;
                foundAsia = true;
            }
            if(m1[i].time >= l_start && m1[i].time <= l_end) {
                if(m1[i].high > lh) lh = m1[i].high;
                if(m1[i].low < ll)  ll = m1[i].low;
                foundLon = true;
            }
        }
        
        if(foundAsia && TimeCurrent() > a_end && AsiaH == EMPTY_VALUE) {
            AsiaH = ah; AsiaL = al;
            DrawLine("CRT_AsiaH", AsiaH, clrDeepSkyBlue);
            DrawLine("CRT_AsiaL", AsiaL, clrDeepSkyBlue);
        }
        if(foundLon && TimeCurrent() > l_end && LonH == EMPTY_VALUE) {
            LonH = lh; LonL = ll;
            DrawLine("CRT_LonH", LonH, clrDodgerBlue);
            DrawLine("CRT_LonL", LonL, clrDodgerBlue);
        }
    }
}

//+------------------------------------------------------------------+
//| Quemado de Liquidez por ATR                                      |
//+------------------------------------------------------------------+
void CheckInvalidationBounds() {
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) <= 0) return;
    double atr = atrBuffer[0];
    double maxDist = atr * InpAtrMultiplier;
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Bullish Pools (Quemado si el Bid baja demasiado del pool)
    if(!c_PDL && PDL!=EMPTY_VALUE && bid < (PDL - maxDist)) { c_PDL = true; RemoveLine("CRT_PDL"); }
    if(!c_PWL && PWL!=EMPTY_VALUE && bid < (PWL - maxDist)) { c_PWL = true; RemoveLine("CRT_PWL"); }
    if(!c_AsiaL && AsiaL!=EMPTY_VALUE && bid < (AsiaL - maxDist)) { c_AsiaL = true; RemoveLine("CRT_AsiaL"); }
    if(!c_LonL && LonL!=EMPTY_VALUE && bid < (LonL - maxDist)) { c_LonL = true; RemoveLine("CRT_LonL"); }
    
    // Bearish Pools (Quemado si el Ask sube demasiado del pool)
    if(!c_PDH && PDH!=EMPTY_VALUE && ask > (PDH + maxDist)) { c_PDH = true; RemoveLine("CRT_PDH"); }
    if(!c_PWH && PWH!=EMPTY_VALUE && ask > (PWH + maxDist)) { c_PWH = true; RemoveLine("CRT_PWH"); }
    if(!c_AsiaH && AsiaH!=EMPTY_VALUE && ask > (AsiaH + maxDist)) { c_AsiaH = true; RemoveLine("CRT_AsiaH"); }
    if(!c_LonH && LonH!=EMPTY_VALUE && ask > (LonH + maxDist)) { c_LonH = true; RemoveLine("CRT_LonH"); }
}

void MarkPoolAsConsumed(string pool) {
    if(pool == "PDH") { c_PDH = true; RemoveLine("CRT_PDH"); }
    if(pool == "PDL") { c_PDL = true; RemoveLine("CRT_PDL"); }
    if(pool == "PWH") { c_PWH = true; RemoveLine("CRT_PWH"); }
    if(pool == "PWL") { c_PWL = true; RemoveLine("CRT_PWL"); }
    if(pool == "AsiaH") { c_AsiaH = true; RemoveLine("CRT_AsiaH"); }
    if(pool == "AsiaL") { c_AsiaL = true; RemoveLine("CRT_AsiaL"); }
    if(pool == "LonH") { c_LonH = true; RemoveLine("CRT_LonH"); }
    if(pool == "LonL") { c_LonL = true; RemoveLine("CRT_LonL"); }
}

//+------------------------------------------------------------------+
//| OnTick - Motor Lógico Principal                                  |
//+------------------------------------------------------------------+
void OnTick() {
    RefreshHTFLevels();
    CheckInvalidationBounds();

    if(PositionsTotal() > 0) return; 

    static datetime lastBar = 0;
    datetime currentBar = iTime(_Symbol, InpLTF, 0);
    bool isNewBar = (currentBar != lastBar);

    if(isNewBar) {
        lastBar = currentBar;
        DetectCRTLogic();
    }
}

void DetectCRTLogic() {
    MqlRates htf[]; if(CopyRates(_Symbol, InpHTF, 0, 3, htf) < 3) return;
    MqlRates ltf[]; if(CopyRates(_Symbol, InpLTF, 0, 3, ltf) < 3) return;
    MqlRates exe[]; int total = CopyRates(_Symbol, PERIOD_CURRENT, 0, InpLookback+1, exe);
    if(total < InpLookback+1) return;

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

    // 1. OBTENER EXTREMOS RECIENTES (Barridas)
    double lowPoint = exe[total-1].low;
    double highPoint = exe[total-1].high;
    for(int k=total-1; k>=total-InpLookback; k--) {
        if(exe[k].low < lowPoint) lowPoint = exe[k].low;
        if(exe[k].high > highPoint) highPoint = exe[k].high;
    }

    // 2. DETECCIÓN ENGULFING EN LTF CON FILTRO DE CUERPO
    double c1_open = ltf[0].open; double c1_close = ltf[0].close; 
    double c2_open = ltf[1].open; double c2_close = ltf[1].close; 
    
    double body1 = MathAbs(c1_close - c1_open);
    double body2 = MathAbs(c2_close - c2_open);

    bool bodyFilter = (body2 > body1); // El cuerpo envolvente debe ser mayor

    bool newBullEngulfing = bodyFilter && (c1_close < c1_open) && (c2_close > c2_open) && (c2_close > c1_open) && (c2_open <= c1_close);
    bool newBearEngulfing = bodyFilter && (c1_close > c1_open) && (c2_close < c2_open) && (c2_close < c1_open) && (c2_open >= c1_close);

    if (!newBullEngulfing && !newBearEngulfing) return;

    // 3. CONTEXTO PO3 HTF
    // Anticipación: htf[1] es la base
    double base_a_h = htf[1].high;
    double base_a_l = htf[1].low;
    
    // Confirmación: htf[0] es la base, htf[1] es la manipuladora
    double base_c_h = htf[0].high;
    double base_c_l = htf[0].low;
    double man_h = htf[1].high;
    double man_l = htf[1].low;
    double man_c = htf[1].close;

    bool htf_bull_anticipation = (bid < base_a_l);
    bool htf_bull_confirmed    = (man_l < base_c_l && man_c >= base_c_l && bid < base_c_h);
    
    bool htf_bear_anticipation = (ask > base_a_h);
    bool htf_bear_confirmed    = (man_h > base_c_h && man_c <= base_c_h && ask > base_c_l);

    // 4. CRUZAR BARRIDA ESTÁTICA + CONTEXTO HTF + GATILLO LTF
    
    // SETUP COMPRA (BULLISH)
    if(newBullEngulfing && (htf_bull_anticipation || htf_bull_confirmed)) {
        string pool = "";
        if(!c_PDL && PDL != EMPTY_VALUE && lowPoint <= PDL) pool = "PDL";
        else if(!c_PWL && PWL != EMPTY_VALUE && lowPoint <= PWL) pool = "PWL";
        else if(!c_AsiaL && AsiaL != EMPTY_VALUE && lowPoint <= AsiaL) pool = "AsiaL";
        else if(!c_LonL && LonL != EMPTY_VALUE && lowPoint <= LonL) pool = "LonL";
        
        if(pool != "") {
            double tp = htf_bull_anticipation ? base_a_h : base_c_h;
            double sl = ltf[1].low;
            if(ask > sl) {
                double rr = (tp - ask) / (ask - sl);
                if(rr >= 1.0) {
                    double lots = CalculateLotSize(ask, sl);
                    if(trade.Buy(lots, _Symbol, ask, sl, tp, "CRT Buy ("+pool+")")) {
                        MarkPoolAsConsumed(pool); return;
                    }
                }
            }
        }
    }

    // SETUP VENTA (BEARISH)
    if(newBearEngulfing && (htf_bear_anticipation || htf_bear_confirmed)) {
        string pool = "";
        if(!c_PDH && PDH != EMPTY_VALUE && highPoint >= PDH) pool = "PDH";
        else if(!c_PWH && PWH != EMPTY_VALUE && highPoint >= PWH) pool = "PWH";
        else if(!c_AsiaH && AsiaH != EMPTY_VALUE && highPoint >= AsiaH) pool = "AsiaH";
        else if(!c_LonH && LonH != EMPTY_VALUE && highPoint >= LonH) pool = "LonH";
        
        if(pool != "") {
            double tp = htf_bear_anticipation ? base_a_l : base_c_l;
            double sl = ltf[1].high;
            if(sl > bid) {
                double rr = (bid - tp) / (sl - bid);
                if(rr >= 1.0) {
                    double lots = CalculateLotSize(bid, sl);
                    if(trade.Sell(lots, _Symbol, bid, sl, tp, "CRT Sell ("+pool+")")) {
                        MarkPoolAsConsumed(pool); return;
                    }
                }
            }
        }
    }
}
//+------------------------------------------------------------------+