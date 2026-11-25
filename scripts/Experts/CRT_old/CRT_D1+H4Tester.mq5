//+------------------------------------------------------------------+
//|                                              CRT_H4_Tester.mq5   |
//| V7 - Instant Execution & 2R Step Trailing Stop (Only DailyTP)    |
//+------------------------------------------------------------------+
#property copyright "CRT Strategy Tester"
#property version   "7.00"
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
input long     InpMagic            = 440801;  

input group    "=== Ventana Operativa (Hora Broker) ==="
// Las horas a las que cierra la vela H4 y queremos operar (Ej: 12 y 16)
input int      InpStartHour        = 12;      
input int      InpEndHour          = 16;      
input int      InpCloseHour        = 22;      
input int      InpCloseMinute      = 50;

input group    "=== Filtro Diario (Master D1) ==="
input bool     InpUseDailyFilter   = true;    

input group    "=== Parámetros SWEEP ==="
input bool     InpEnableSweep      = true;    
input double   InpSweepMinRR       = 1.0;     // Solo opera si Rango > 1:1

input group    "=== Parámetros RUN ==="
input bool     InpEnableRun        = true;    
input double   InpMinRunTPPips     = 5.0;     
input double   InpMinRunSLPips     = 5.0;     

input group    "=== Trailing Stop (Solo RUN_DailyTP) ==="
input bool     InpEnableTrailingRR = true;    
// El TS asegurará +1R solo cuando el precio alcance +2R

input group    "=== Filtros Generales H4 ==="
input double   InpMinPips          = 5.0;     
input double   InpSpreadBufferPips = 2.0;     

//--- Variables Globales
datetime       g_lastH4Bar = 0;
double         g_pipSize = 0;

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

   // 2. Gestionar Trailing Stop por Ratios (Tic a Tic)
   if(InpEnableTrailingRR) ManageTrailingStop_ByRR();

   // 3. Evaluar nueva vela H4 (EJECUCIÓN INSTANTÁNEA)
   if(dt.hour < InpStartHour || dt.hour > InpEndHour) return;

   datetime currentH4Bar = iTime(_Symbol, PERIOD_H4, 0);
   if(currentH4Bar == g_lastH4Bar) return; 
   g_lastH4Bar = currentH4Bar;

   if(HasOpenPosition()) return;

   double high1  = iHigh(_Symbol, PERIOD_H4, 1);
   double low1   = iLow(_Symbol, PERIOD_H4, 1);
   double close1 = iClose(_Symbol, PERIOD_H4, 1);
   double high2  = iHigh(_Symbol, PERIOD_H4, 2);
   double low2   = iLow(_Symbol, PERIOD_H4, 2);
   
   int signal = 0; 
   double sl = 0, tp = 0;
   string comment = "";

   double ask = symInfo.Ask();
   double bid = symInfo.Bid();
   double buffer = InpSpreadBufferPips * g_pipSize;

   int dailyBias = 0;
   if(InpUseDailyFilter) dailyBias = GetDailyBias();

   // --- LÓGICA SWEEP (Solo Estructural > 1:1) ---
   if(InpEnableSweep)
   {
      double candleSizePips = (high1 - low1) / g_pipSize;
      if(candleSizePips >= InpMinPips)
      {
         bool isBullSweep = (low1 < low2 && close1 > low2 && high1 <= high2);
         bool isBearSweep = (high1 > high2 && close1 < high2 && low1 >= low2);

         if(InpUseDailyFilter)
         {
            if(isBullSweep && dailyBias != 1) isBullSweep = false; 
            if(isBearSweep && dailyBias != -1) isBearSweep = false; 
         }

         if(isBullSweep)
         {
            double temp_sl = low1 - buffer;
            double risk = ask - temp_sl;
            double structuralReward = high2 - ask; 
            
            if(structuralReward >= (risk * InpSweepMinRR))
            {
               signal = 1; sl = temp_sl; tp = high2; comment = "H4_SWEEP_BUY_StructTP";
            }
         }
         else if(isBearSweep)
         {
            double temp_sl = high1 + buffer;
            double risk = temp_sl - bid;
            double structuralReward = bid - low2; 
            
            if(structuralReward >= (risk * InpSweepMinRR))
            {
               signal = -1; sl = temp_sl; tp = low2; comment = "H4_SWEEP_SELL_StructTP";
            }
         }
      }
   }

   // --- LÓGICA RUN ---
   if(InpEnableRun && signal == 0)
   {
      if(close1 > high2) // Alcista
      {
         double distTPPips = (high1 - ask) / g_pipSize;
         if(distTPPips >= InpMinRunTPPips)
         {
            signal = 1;
            double structural_sl = low1 - buffer;
            if((ask - structural_sl) / g_pipSize < InpMinRunSLPips) sl = ask - (distTPPips * g_pipSize) - buffer;
            else sl = structural_sl;
            
            double dailyTarget = GetDailyTarget(1);
            if(dailyBias == 1 && dailyTarget > ask + (InpMinPips * g_pipSize)) 
            { tp = dailyTarget; comment = "H4_RUN_BUY_DailyTP"; } 
            else { tp = high1; comment = (sl == structural_sl) ? "H4_RUN_BUY_Struct" : "H4_RUN_BUY_1to1"; }
         }
      }
      else if(close1 < low2) // Bajista
      {
         double distTPPips = (bid - low1) / g_pipSize;
         if(distTPPips >= InpMinRunTPPips)
         {
            signal = -1;
            double structural_sl = high1 + buffer;
            if((structural_sl - bid) / g_pipSize < InpMinRunSLPips) sl = bid + (distTPPips * g_pipSize) + buffer;
            else sl = structural_sl;
            
            double dailyTarget = GetDailyTarget(-1);
            if(dailyBias == -1 && dailyTarget < bid - (InpMinPips * g_pipSize) && dailyTarget != 0) 
            { tp = dailyTarget; comment = "H4_RUN_SELL_DailyTP"; } 
            else { tp = low1; comment = (sl == structural_sl) ? "H4_RUN_SELL_Struct" : "H4_RUN_SELL_1to1"; }
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
//| Step Trailing Stop Basado en Ratios (R:R) - Activación en +2R    |
//+------------------------------------------------------------------+
void ManageTrailingStop_ByRR()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
         {
            // SOLO aplicar a las operaciones RUN_DailyTP
            if(StringFind(posInfo.Comment(), "DailyTP") >= 0)
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
                     ulong order_ticket = HistoryOrderGetTicket(o);
                     if(HistoryOrderGetInteger(order_ticket, ORDER_POSITION_ID) == posInfo.Identifier())
                     {
                        double sl = HistoryOrderGetDouble(order_ticket, ORDER_SL);
                        if(sl > 0) { initial_SL = sl; break; }
                     }
                  }
               }
               
               if(initial_SL == 0) continue;
               
               double risk = MathAbs(openPrice - initial_SL);
               if(risk <= 0) continue;

               double currentProfit = MathAbs(currentPrice - openPrice);
               int currentR = (int)MathFloor(currentProfit / risk);

               // NUEVO: Solo actuamos si el precio ha llegado al menos a +2R
               if(currentR >= 2)
               {
                  double newSL = 0;
                  
                  if(posInfo.PositionType() == POSITION_TYPE_BUY)
                  {
                     // Si estamos en 2R, aseguramos 1R. Si estamos en 3R, aseguramos 2R.
                     newSL = openPrice + ((currentR - 1) * risk);
                     
                     // Solo modificar si el nuevo SL es mejor que el actual (+ spread safety)
                     if(newSL > currentSL + (g_pipSize * 2))
                     {
                        trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
                     }
                  }
                  else if(posInfo.PositionType() == POSITION_TYPE_SELL)
                  {
                     newSL = openPrice - ((currentR - 1) * risk);
                     
                     if(newSL < currentSL - (g_pipSize * 2) || currentSL == 0)
                     {
                        trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
                     }
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
int GetDailyBias() {
   double d1_high1 = iHigh(_Symbol, PERIOD_D1, 1);
   double d1_low1  = iLow(_Symbol, PERIOD_D1, 1);
   double d1_close1= iClose(_Symbol, PERIOD_D1, 1);
   double d1_high2 = iHigh(_Symbol, PERIOD_D1, 2);
   double d1_low2  = iLow(_Symbol, PERIOD_D1, 2);
   
   if(d1_close1 > d1_high2) return 1;  
   if(d1_close1 < d1_low2) return -1; 
   if(d1_low1 < d1_low2 && d1_close1 > d1_low2 && d1_high1 <= d1_high2) return 1;
   if(d1_high1 > d1_high2 && d1_close1 < d1_high2 && d1_low1 >= d1_low2) return -1;
   return 0; 
}

double GetDailyTarget(int bias) {
   if(bias == 1) return MathMax(iHigh(_Symbol, PERIOD_D1, 1), iHigh(_Symbol, PERIOD_D1, 2));
   if(bias == -1) return MathMin(iLow(_Symbol, PERIOD_D1, 1), iLow(_Symbol, PERIOD_D1, 2));
   return 0;
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
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic) trade.PositionClose(posInfo.Ticket());
   }
}

bool HasOpenPosition() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic) return true;
   }
   return false;
}