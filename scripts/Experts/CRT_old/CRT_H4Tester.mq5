//+------------------------------------------------------------------+
//|                                              CRT_H4_Tester.mq5   |
//|            Backtest CRT H4 Direction + Session Sweep Filter      |
//+------------------------------------------------------------------+
#property copyright "CRT Strategy Tester"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

//--- Inputs
input group    "=== Riesgo y Gestión ==="
input double   InpRiskPercent      = 1.0;     // Riesgo % por operación
input long     InpMagic            = 440801;  // Magic Number H4

input group    "=== Ventana Operativa (Hora Broker) ==="
input int      InpStartHour        = 7;       // Permitir entradas desde (ej. 07:00)
input int      InpEndHour          = 16;      // Permitir entradas hasta (ej. 16:00 -> Evita vela 19:00)
input int      InpCloseHour        = 22;      // Hora cierre forzado
input int      InpCloseMinute      = 50;

input group    "=== Sesiones y Liquidez (Hora Broker) ==="
input int      InpAsiaStart        = 0;       // Inicio Asia
input int      InpAsiaEnd          = 7;       // Fin Asia (Apertura Frankfurt/Londres)
input int      InpLonStart         = 7;       // Inicio Londres
input int      InpLonEnd           = 15;      // Fin Londres (Apertura NY)
input bool     InpRequireSessionSweep = false;// true = El Sweep H4 DEBE barrer Asia o Londres
input bool     InpDrawSessions     = true;    // Dibujar las cajas en el gráfico

input group    "=== Filtros Generales H4 ==="
input double   InpMinPips          = 5.0;     // Tamaño mínimo de vela H4 en pips
input double   InpSpreadBufferPips = 2.0;     // Pips extra de respiro para el SL
input bool     InpEnableSweep      = true;    // Activar setup SWEEP
input bool     InpEnableRun        = true;    // Activar setup RUN

input group    "=== Parametros RUN ==="
input double   InpMinRunTPPips     = 5.0;     // Mínimo de pips de mecha (TP) para operar RUN
input double   InpMinRunSLPips     = 5.0;     // Mínimo de pips para usar SL Estructural


//--- Variables Globales
datetime       g_lastH4Bar = 0;
double         g_pipSize = 0;
double         g_asiaHigh = 0, g_asiaLow = 0;
double         g_lonHigh = 0, g_lonLow = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   symInfo.Name(_Symbol);
   symInfo.Refresh();
   
   g_pipSize = _Point;
   if(_Digits == 3 || _Digits == 5) g_pipSize *= 10;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
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

   // 2. Filtro de Ventana Operativa (No evalúa señales fuera de este rango)
   if(dt.hour < InpStartHour || dt.hour > InpEndHour) return;

   // 3. Detectar nueva vela de H4
   datetime currentH4Bar = iTime(_Symbol, PERIOD_H4, 0);
   if(currentH4Bar == g_lastH4Bar) return; 

   g_lastH4Bar = currentH4Bar;

   // 4. Actualizar Niveles de Sesión del Día Actual
   UpdateSessionLevels(TimeCurrent());

   // 5. Control de sobre-exposición
   if(HasOpenPosition()) return;

   // 6. Obtener datos H4
   double high1  = iHigh(_Symbol, PERIOD_H4, 1);
   double low1   = iLow(_Symbol, PERIOD_H4, 1);
   double close1 = iClose(_Symbol, PERIOD_H4, 1);
   
   double high2  = iHigh(_Symbol, PERIOD_H4, 2);
   double low2   = iLow(_Symbol, PERIOD_H4, 2);
   
   int signal = 0; 
   double sl = 0;
   double tp = 0;
   string comment = "";

   double ask = symInfo.Ask();
   double bid = symInfo.Bid();
   double buffer = InpSpreadBufferPips * g_pipSize;

   // --- LÓGICA SWEEP ---
   if(InpEnableSweep)
   {
      double candleSizePips = (high1 - low1) / g_pipSize;
      if(candleSizePips >= InpMinPips)
      {
         bool isBullSweep = (low1 < low2 && close1 > low2 && high1 <= high2);
         bool isBearSweep = (high1 > high2 && close1 < high2 && low1 >= low2);
         
         // Filtro extra: ¿Barrer liquidez de Asia o Londres?
         if(InpRequireSessionSweep)
         {
            if(isBullSweep && !(low1 < g_asiaLow || (g_lonLow > 0 && low1 < g_lonLow))) isBullSweep = false;
            if(isBearSweep && !(high1 > g_asiaHigh || (g_lonHigh > 0 && high1 > g_lonHigh))) isBearSweep = false;
         }

         if(isBullSweep)
         {
            signal = 1;
            sl = low1 - buffer; 
            tp = high2; 
            comment = InpRequireSessionSweep ? "H4_LIQ_SWEEP_BUY" : "H4_SWEEP_BUY";
         }
         else if(isBearSweep)
         {
            signal = -1;
            sl = high1 + buffer; 
            tp = low2; 
            comment = InpRequireSessionSweep ? "H4_LIQ_SWEEP_SELL" : "H4_SWEEP_SELL";
         }
      }
   }

   // --- LÓGICA RUN (Continuación estructural) ---
   if(InpEnableRun && signal == 0)
   {
      if(close1 > high2) // Alcista
      {
         double distTPPips = (high1 - ask) / g_pipSize;
         if(distTPPips >= InpMinRunTPPips)
         {
            signal = 1;
            tp = high1; 
            double structural_sl = low1 - buffer;
            if((ask - structural_sl) / g_pipSize < InpMinRunSLPips) 
            {
               sl = ask - (distTPPips * g_pipSize) - buffer;
               comment = "H4_RUN_BUY_1to1"; 
            } 
            else 
            {
               sl = structural_sl;
               comment = "H4_RUN_BUY_Struct"; 
            }
         }
      }
      else if(close1 < low2) // Bajista
      {
         double distTPPips = (bid - low1) / g_pipSize;
         if(distTPPips >= InpMinRunTPPips)
         {
            signal = -1;
            tp = low1; 
            double structural_sl = high1 + buffer;
            if((structural_sl - bid) / g_pipSize < InpMinRunSLPips) 
            {
               sl = bid + (distTPPips * g_pipSize) + buffer;
               comment = "H4_RUN_SELL_1to1";
            } 
            else 
            {
               sl = structural_sl;
               comment = "H4_RUN_SELL_Struct";
            }
         }
      }
   }

   // --- EJECUTAR OPERACIÓN ---
   if(signal != 0)
   {
      double entryPrice = (signal == 1) ? ask : bid;
      double lotSize = CalculateLotSize(sl, entryPrice);
      if(lotSize > 0)
      {
         if(signal == 1) trade.Buy(lotSize, _Symbol, ask, sl, tp, comment);
         else trade.Sell(lotSize, _Symbol, bid, sl, tp, comment);
      }
   }
}

//+------------------------------------------------------------------+
//| Calcula Máximos y Mínimos de las Sesiones del día actual         |
//+------------------------------------------------------------------+
void UpdateSessionLevels(datetime currentTime)
{
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime midnight = StructToTime(dt);

   datetime asiaStart = midnight + (InpAsiaStart * 3600);
   datetime asiaEnd   = midnight + (InpAsiaEnd * 3600);
   datetime lonStart  = midnight + (InpLonStart * 3600);
   datetime lonEnd    = midnight + (InpLonEnd * 3600);

   // Arrays para guardar datos
   double high[], low[];
   
   // Obtener Liquidez de Asia
   if(currentTime >= asiaEnd) 
   {
      if(CopyHigh(_Symbol, PERIOD_M15, asiaStart, asiaEnd, high) > 0) g_asiaHigh = high[ArrayMaximum(high)];
      if(CopyLow(_Symbol, PERIOD_M15, asiaStart, asiaEnd, low) > 0) g_asiaLow = low[ArrayMinimum(low)];
      
      if(InpDrawSessions) DrawSessionBox("Box_Asia_"+TimeToString(midnight), asiaStart, asiaEnd, g_asiaHigh, g_asiaLow, clrLightSkyBlue);
   }

   // Obtener Liquidez de Londres (Solo si ya pasamos la apertura)
   if(currentTime >= lonStart)
   {
      datetime endSearch = (currentTime < lonEnd) ? currentTime : lonEnd;
      if(CopyHigh(_Symbol, PERIOD_M15, lonStart, endSearch, high) > 0) g_lonHigh = high[ArrayMaximum(high)];
      if(CopyLow(_Symbol, PERIOD_M15, lonStart, endSearch, low) > 0) g_lonLow = low[ArrayMinimum(low)];
      
      if(InpDrawSessions && currentTime >= lonEnd) DrawSessionBox("Box_Lon_"+TimeToString(midnight), lonStart, lonEnd, g_lonHigh, g_lonLow, clrLightCoral);
   }
}

//+------------------------------------------------------------------+
//| Dibuja los rectángulos de las sesiones (Modo Visual)             |
//+------------------------------------------------------------------+
void DrawSessionBox(string name, datetime startT, datetime endT, double pHigh, double pLow, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, startT, pHigh, endT, pLow);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, 0, pHigh);
      ObjectSetDouble(0, name, OBJPROP_PRICE, 1, pLow);
      ObjectSetInteger(0, name, OBJPROP_TIME, 1, endT);
   }
}

//+------------------------------------------------------------------+
//| Funciones de Gestión                                             |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_price, double entry_price)
{
   double risk_amount = AccountInfoDouble(ACCOUNT_BALANCE) * (InpRiskPercent / 100.0);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double loss_ticks = MathAbs(entry_price - sl_price) / tick_size;
   if(loss_ticks <= 0) return 0;
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return MathFloor((risk_amount / (loss_ticks * tick_value)) / lot_step) * lot_step;
}

void CloseAllPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic) trade.PositionClose(posInfo.Ticket());
   }
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic) return true;
   }
   return false;
}