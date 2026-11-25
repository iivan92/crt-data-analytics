//+------------------------------------------------------------------+
//|                                    CRT_Fractal_Liq_V18.1.mq5     |
//| V18.1 - Full Liquidity Filter + Double Time Window (Lon & NY)    |
//+------------------------------------------------------------------+
#property copyright "CRT Strategy Tester"
#property version   "18.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

//--- Inputs
input group    "=== Riesgo y Gestión ==="
input double   InpRiskPercent      = 1.0;     
input long     InpMagic            = 181801;  

input group    "=== Ventanas Operativas (Hora Broker) ==="
input int      InpLonStartHour     = 9;       // Inicio ventana Londres
input int      InpLonEndHour       = 11;      // Fin ventana Londres
input int      InpNYStartHour      = 16;      // Inicio ventana NY
input int      InpNYEndHour        = 18;      // Fin ventana NY
input int      InpCloseHour        = 22;      // Hora cierre forzado
input int      InpCloseMinute      = 50;

input group    "=== Filtro de Liquidez ==="
input bool     InpUseLiquidityFilter = true;  // Exige barrer liquidez para entrar
input int      InpMaxBarsSinceSweep  = 4;     // Margen de 4 horas (velas H1)

input group    "=== Horarios de Sesiones (Broker Time) ==="
input int      InpAsiaStart        = 0;
input int      InpAsiaEnd          = 8;       
input int      InpLonStart         = 9;       
input int      InpLonEnd           = 14;      

input group    "=== Gestión Estructural de Salida ==="
input double   InpMinSLPips        = 5.0;     
input double   InpTargetRR         = 3.0;     // Límite RatioCap

input group    "=== Break Even & Step Trailing ==="
input bool     InpEnableBE         = true;    
input double   InpBE_ActivationRR  = 1.0;     
input double   InpBE_BufferPips    = 0.5;     
input bool     InpEnableTS         = true;    
input double   InpTS_ActivationRR  = 2.0;     

input group    "=== Filtros del Patrón ==="
input double   InpMinPipsH1        = 3.0;     
input double   InpSpreadBufferPips = 2.0;     

input group    "=== Debug Visual ==="
input bool     InpDrawLevels       = false;   // Poner a true para test visual

//--- Variables Globales
double g_asiaH = 0, g_asiaL = 0;
double g_lonH  = 0, g_lonL  = 0;
double g_pdh   = 0, g_pdl   = 0;
double g_pwh   = 0, g_pwl   = 0;

datetime g_lastH1Bar = 0;
double   g_pipSize = 0;
int      g_objCount = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   g_pipSize = _Point;
   if(_Digits == 3 || _Digits == 5) g_pipSize *= 10;
   
   if(InpDrawLevels) ObjectsDeleteAll(0, "CRT_");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(InpDrawLevels) ObjectsDeleteAll(0, "CRT_");
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!symInfo.RefreshRates()) return;
   MqlDateTime dt;
   TimeCurrent(dt);

   // 1. Cierre forzado fin de día
   if(dt.hour == InpCloseHour && dt.min >= InpCloseMinute)
   {
      CloseAllPositions();
      return; 
   }

   // 2. Gestión de Break Even y Trailing
   if(HasOpenPosition()) ManageTradeExit();

   // 3. Actualizar niveles de liquidez (Siempre se actualiza en segundo plano)
   UpdateLiquidityLevels(dt);

   // 4. FILTRO HORARIO (Doble Ventana)
   bool isInLondon = (dt.hour >= InpLonStartHour && dt.hour <= InpLonEndHour);
   bool isInNY     = (dt.hour >= InpNYStartHour && dt.hour <= InpNYEndHour);
   
   if(!isInLondon && !isInNY) return;

   // 5. Evaluar solo al Cierre de Vela H1
   datetime currentH1Bar = iTime(_Symbol, PERIOD_H1, 0);
   if(currentH1Bar == g_lastH1Bar) return; 
   g_lastH1Bar = currentH1Bar;

   if(HasOpenPosition()) return;

   // --- FASE 1: DATOS H1 ---
   double h1_high1  = iHigh(_Symbol, PERIOD_H1, 1);
   double h1_low1   = iLow(_Symbol, PERIOD_H1, 1);
   double h1_close1 = iClose(_Symbol, PERIOD_H1, 1);
   double h1_high2  = iHigh(_Symbol, PERIOD_H1, 2);
   double h1_low2   = iLow(_Symbol, PERIOD_H1, 2);

   double h1_candleSize = (h1_high1 - h1_low1) / g_pipSize;
   if(h1_candleSize < InpMinPipsH1) return; 

   bool isH1BullSweep = (h1_low1 < h1_low2 && h1_close1 > h1_low2 && h1_high1 <= h1_high2);
   bool isH1BearSweep = (h1_high1 > h1_high2 && h1_close1 < h1_high2 && h1_low1 >= h1_low2);

   if(!isH1BullSweep && !isH1BearSweep) return; 

   // --- FASE 2: DATOS H4 ---
   double h4_high0  = iHigh(_Symbol, PERIOD_H4, 0); 
   double h4_low0   = iLow(_Symbol, PERIOD_H4, 0);  
   double h4_high1  = iHigh(_Symbol, PERIOD_H4, 1); 
   double h4_low1   = iLow(_Symbol, PERIOD_H4, 1);  

   double ask = symInfo.Ask();
   double bid = symInfo.Bid();
   double buffer = InpSpreadBufferPips * g_pipSize;

   int signal = 0;
   double sl = 0, tp = 0;
   string baseComment = "";
   double rangeHigh = 0, rangeLow = 0;

   // --- LÓGICA ALCISTA ---
   if(isH1BullSweep && (h4_low0 < h4_low1 && ask > h4_low1))
   {
      double lowestPoint = MathMin(h1_low1, h4_low0);
      bool isFreshSweep = false;
      
      if(InpUseLiquidityFilter) 
      {
         if(lowestPoint < g_pwl && IsLevelFresh(g_pwl, 1)) { isFreshSweep = true; baseComment = "B_PWL"; }
         else if(lowestPoint < g_pdl && IsLevelFresh(g_pdl, 1)) { isFreshSweep = true; baseComment = "B_PDL"; }
         else if(g_lonL > 0 && lowestPoint < g_lonL && IsLevelFresh(g_lonL, 1)) { isFreshSweep = true; baseComment = "B_LoL"; }
         else if(g_asiaL > 0 && lowestPoint < g_asiaL && IsLevelFresh(g_asiaL, 1)) { isFreshSweep = true; baseComment = "B_AsL"; }
      } 
      else { isFreshSweep = true; baseComment = "B_NoLiq"; }

      if(isFreshSweep)
      {
         double entryPrice = ask;
         double temp_sl = h4_low0 - buffer;
         if((entryPrice - temp_sl) / g_pipSize < InpMinSLPips) temp_sl = entryPrice - (InpMinSLPips * g_pipSize);
         
         double risk = entryPrice - temp_sl;
         double struct_reward = h4_high1 - entryPrice;
         
         if(struct_reward >= risk)
         {
            signal = 1; sl = temp_sl;
            rangeHigh = h4_high1; rangeLow = h4_low0;
            
            double limit_reward = risk * InpTargetRR;
            if(struct_reward > limit_reward) { tp = entryPrice + limit_reward; baseComment += "_Cap"; }
            else { tp = h4_high1; baseComment += "_Rng"; }
         }
      }
   }
   
   // --- LÓGICA BAJISTA ---
   else if(isH1BearSweep && (h4_high0 > h4_high1 && bid < h4_high1))
   {
      double highestPoint = MathMax(h1_high1, h4_high0);
      bool isFreshSweep = false;
      
      if(InpUseLiquidityFilter) 
      {
         if(highestPoint > g_pwh && IsLevelFresh(g_pwh, -1)) { isFreshSweep = true; baseComment = "S_PWH"; }
         else if(highestPoint > g_pdh && IsLevelFresh(g_pdh, -1)) { isFreshSweep = true; baseComment = "S_PDH"; }
         else if(g_lonH > 0 && highestPoint > g_lonH && IsLevelFresh(g_lonH, -1)) { isFreshSweep = true; baseComment = "S_LoH"; }
         else if(g_asiaH > 0 && highestPoint > g_asiaH && IsLevelFresh(g_asiaH, -1)) { isFreshSweep = true; baseComment = "S_AsH"; }
      } 
      else { isFreshSweep = true; baseComment = "S_NoLiq"; }

      if(isFreshSweep)
      {
         double entryPrice = bid;
         double temp_sl = h4_high0 + buffer;
         if((temp_sl - entryPrice) / g_pipSize < InpMinSLPips) temp_sl = entryPrice + (InpMinSLPips * g_pipSize);
         
         double risk = temp_sl - entryPrice;
         double struct_reward = entryPrice - h4_low1;
         
         if(struct_reward >= risk)
         {
            signal = -1; sl = temp_sl;
            rangeHigh = h4_high0; rangeLow = h4_low1;
            
            double limit_reward = risk * InpTargetRR;
            if(struct_reward > limit_reward) { tp = entryPrice - limit_reward; baseComment += "_Cap"; }
            else { tp = h4_low1; baseComment += "_Rng"; }
         }
      }
   }

   // --- FASE 3: EJECUCIÓN ---
   if(signal != 0)
   {
      double entryPrice = (signal == 1) ? ask : bid;
      double lotSize = CalculateLotSize(sl, entryPrice);
      if(lotSize > 0)
      {
         if(signal == 1) trade.Buy(lotSize, _Symbol, ask, sl, tp, baseComment);
         else trade.Sell(lotSize, _Symbol, bid, sl, tp, baseComment);
         
         if(InpDrawLevels) DrawTradeRange(rangeHigh, rangeLow);
      }
   }
}

//+------------------------------------------------------------------+
//| Filtro de Frescura de Liquidez                                   |
//+------------------------------------------------------------------+
bool IsLevelFresh(double level, int direction)
{
   int barsToCheck = InpMaxBarsSinceSweep + 1; 
   for(int i = 1; i <= barsToCheck; i++)
   {
      double h1_low = iLow(_Symbol, PERIOD_H1, i);
      double h1_high = iHigh(_Symbol, PERIOD_H1, i);
      
      if(direction == 1 && h1_low < level) return (i <= InpMaxBarsSinceSweep);
      else if(direction == -1 && h1_high > level) return (i <= InpMaxBarsSinceSweep);
   }
   return false;
}

//+------------------------------------------------------------------+
//| Actualización de Liquidez y DIBUJO (Con Reseteo Diario)          |
//+------------------------------------------------------------------+
void UpdateLiquidityLevels(MqlDateTime &dt)
{
   static int lastDay = -1;
   datetime currentHourTime = TimeCurrent() - (dt.min*60 + dt.sec);
   
   if(dt.day != lastDay) {
      g_lonH = 0; g_lonL = 0; 
      g_asiaH = 0; g_asiaL = 0; 
      
      if(InpDrawLevels) ObjectsDeleteAll(0, "CRT_");
      
      g_pdh = iHigh(_Symbol, PERIOD_D1, 1);
      g_pdl = iLow(_Symbol, PERIOD_D1, 1);
      g_pwh = iHigh(_Symbol, PERIOD_W1, 1);
      g_pwl = iLow(_Symbol, PERIOD_W1, 1);
      lastDay = dt.day;
      
      if(InpDrawLevels) {
         DrawHorizontalLine("CRT_PDH_"+(string)lastDay, g_pdh, clrRed, "PDH");
         DrawHorizontalLine("CRT_PDL_"+(string)lastDay, g_pdl, clrLime, "PDL");
         DrawHorizontalLine("CRT_PWH_"+(string)lastDay, g_pwh, clrDarkOrange, "PWH");
         DrawHorizontalLine("CRT_PWL_"+(string)lastDay, g_pwl, clrYellow, "PWL");
      }
   }
   
   datetime midnight = TimeCurrent() - (dt.hour*3600 + dt.min*60 + dt.sec);
   double h[], l[];
   
   if(dt.hour == InpAsiaStart && dt.min == 0 && InpDrawLevels) DrawVerticalLine("CRT_Asia_S_"+(string)currentHourTime, currentHourTime, clrDarkGreen);
   
   if(dt.hour == InpAsiaEnd && g_asiaH == 0) { 
      if(CopyHigh(_Symbol, PERIOD_M15, midnight + InpAsiaStart*3600, midnight + InpAsiaEnd*3600, h) > 0) g_asiaH = h[ArrayMaximum(h)];
      if(CopyLow(_Symbol, PERIOD_M15, midnight + InpAsiaStart*3600, midnight + InpAsiaEnd*3600, l) > 0) g_asiaL = l[ArrayMinimum(l)];
      
      if(InpDrawLevels) {
         DrawVerticalLine("CRT_Asia_E_"+(string)currentHourTime, currentHourTime, clrDarkGreen);
         DrawHorizontalLine("CRT_AsiaH_"+(string)dt.day, g_asiaH, clrMediumSeaGreen, "AsiaH");
         DrawHorizontalLine("CRT_AsiaL_"+(string)dt.day, g_asiaL, clrMediumSeaGreen, "AsiaL");
      }
   }
   
   if(dt.hour == InpLonStart && dt.min == 0 && InpDrawLevels) DrawVerticalLine("CRT_Lon_S_"+(string)currentHourTime, currentHourTime, clrNavy);
   
   if(dt.hour == InpLonEnd && g_lonH == 0) { 
      if(CopyHigh(_Symbol, PERIOD_M15, midnight + InpLonStart*3600, midnight + InpLonEnd*3600, h) > 0) g_lonH = h[ArrayMaximum(h)];
      if(CopyLow(_Symbol, PERIOD_M15, midnight + InpLonStart*3600, midnight + InpLonEnd*3600, l) > 0) g_lonL = l[ArrayMinimum(l)];
      
      if(InpDrawLevels) {
         DrawVerticalLine("CRT_Lon_E_"+(string)currentHourTime, currentHourTime, clrNavy);
         DrawHorizontalLine("CRT_LonH_"+(string)dt.day, g_lonH, clrDodgerBlue, "LonH");
         DrawHorizontalLine("CRT_LonL_"+(string)dt.day, g_lonL, clrDodgerBlue, "LonL");
      }
   }
}

//+------------------------------------------------------------------+
//| Funciones de Dibujo (Chart Objects)                              |
//+------------------------------------------------------------------+
void DrawHorizontalLine(string name, double price, color clr, string tooltip)
{
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }
}

void DrawVerticalLine(string name, datetime time, color clr)
{
   if(ObjectFind(0, name) < 0) {
      ObjectCreate(0, name, OBJ_VLINE, 0, time, 0);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
}

void DrawTradeRange(double high, double low)
{
   string name = "CRT_Rect_" + (string)(g_objCount++);
   datetime time1 = iTime(_Symbol, PERIOD_H4, 1); 
   datetime time2 = TimeCurrent(); 
   
   ObjectCreate(0, name, OBJ_RECTANGLE, 0, time1, high, time2, low);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrDarkViolet);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_BACK, true); 
}

//+------------------------------------------------------------------+
//| Gestión de Salida                                                |
//+------------------------------------------------------------------+
void ManageTradeExit()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i) && posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
      {
         double openPrice = posInfo.PriceOpen();
         double currentSL = posInfo.StopLoss();
         double currentPrice = (posInfo.PositionType() == POSITION_TYPE_BUY) ? symInfo.Bid() : symInfo.Ask();
         
         double initial_SL = 0;
         if(HistorySelectByPosition(posInfo.Identifier()))
         {
            int orders = HistoryOrdersTotal();
            for(int o = 0; o < orders; o++)
            {
               ulong ticket = HistoryOrderGetTicket(o);
               if(HistoryOrderGetInteger(ticket, ORDER_POSITION_ID) == posInfo.Identifier())
               {
                  double sl = HistoryOrderGetDouble(ticket, ORDER_SL);
                  if(sl > 0) { initial_SL = sl; break; }
               }
            }
         }
         
         if(initial_SL == 0) continue; 
         double risk = MathAbs(openPrice - initial_SL);
         if(risk <= 0) continue;

         double currentProfit = MathAbs(currentPrice - openPrice);
         double currentR_float = currentProfit / risk; 
         int currentR_int = (int)MathFloor(currentR_float); 

         double newSL = currentSL;
         bool modify = false;
         double be_buffer = InpBE_BufferPips * g_pipSize;

         if(posInfo.PositionType() == POSITION_TYPE_BUY)
         {
            if(InpEnableBE && currentR_float >= InpBE_ActivationRR && currentSL < openPrice) { newSL = openPrice + be_buffer; modify = true; }
            else if(InpEnableTS && currentR_int >= InpTS_ActivationRR) {
               double tempSL = openPrice + ((currentR_int - 1) * risk);
               if(tempSL > currentSL + (g_pipSize * 1)) { newSL = tempSL; modify = true; }
            }
         }
         else if(posInfo.PositionType() == POSITION_TYPE_SELL)
         {
            if(InpEnableBE && currentR_float >= InpBE_ActivationRR && (currentSL > openPrice || currentSL == 0)) { newSL = openPrice - be_buffer; modify = true; }
            else if(InpEnableTS && currentR_int >= InpTS_ActivationRR) {
               double tempSL = openPrice - ((currentR_int - 1) * risk);
               if(tempSL < currentSL - (g_pipSize * 1) || currentSL == 0) { newSL = tempSL; modify = true; }
            }
         }

         if(modify) trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
      }
   }
}

double CalculateLotSize(double sl_price, double entry_price) {
   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double loss_ticks = MathAbs(entry_price - sl_price) / tick_size;
   if(loss_ticks <= 0) return 0;
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathFloor((risk_amount / (loss_ticks * tick_value)) / lot_step) * lot_step;
}
void CloseAllPositions() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) 
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == InpMagic) trade.PositionClose(posInfo.Ticket());
}
bool HasOpenPosition() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) 
      if(posInfo.SelectByIndex(i) && posInfo.Magic() == InpMagic) return true;
   return false;
}