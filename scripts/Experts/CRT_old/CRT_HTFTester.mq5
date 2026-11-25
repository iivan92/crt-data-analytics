//+------------------------------------------------------------------+
//|                                              CRT_MasterBot.mq5   |
//| V9 - Top-Down Master (D1 Bias -> H4 Sweep -> H1 Run Trigger)     |
//+------------------------------------------------------------------+
#property copyright "CRT Strategy Tester"
#property version   "9.00"
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
input long     InpMagic            = 990801;  // Magic Master

input group    "=== Horarios de Contexto H4 ==="
input int      InpH4EvalHour1      = 12;      // Evaluar cierre H4 de la mañana (Pre-NY)
input int      InpH4EvalHour2      = 16;      // Evaluar cierre H4 de la tarde (NY Mid)
input int      InpCloseHour        = 22;      
input int      InpCloseMinute      = 50;

input group    "=== Filtros Estructurales ==="
input double   InpMinH4Pips        = 5.0;     // Tamaño mínimo del Sweep H4
input double   InpMinH1RunPips     = 3.0;     // Tamaño mínimo del Run H1
input double   InpSpreadBufferPips = 2.0;     // Buffer SL

input group    "=== Trailing Stop (Ratio RR) ==="
input bool     InpEnableTrailingRR = true;    // Activar TS Step 

//--- Variables Globales (Modo Caza)
datetime       g_lastH4Bar = 0;
datetime       g_lastH1Bar = 0;
int            g_hunting_bias = 0;      // 1 = Buscando Run Alcista H1, -1 = Buscando Run Bajista H1
datetime       g_hunting_expiry = 0;    // Hora a la que caduca el setup de H4
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
      g_hunting_bias = 0; // Cancelar modo caza
      return; 
   }

   // 2. Trailing Stop
   if(InpEnableTrailingRR) ManageTrailingStop_ByRR();

   // --- FASE 1: EVALUAR CONTEXTO H4 (La Trampa) ---
   datetime currentH4Bar = iTime(_Symbol, PERIOD_H4, 0);
   if(currentH4Bar != g_lastH4Bar)
   {
      g_lastH4Bar = currentH4Bar;
      
      // Solo nos importan los cierres a las horas clave que probamos rentables
      if(dt.hour == InpH4EvalHour1 || dt.hour == InpH4EvalHour2)
      {
         int dailyBias = GetDailyBias();
         
         if(dailyBias != 0 && !HasOpenPosition())
         {
            double h4_high1  = iHigh(_Symbol, PERIOD_H4, 1);
            double h4_low1   = iLow(_Symbol, PERIOD_H4, 1);
            double h4_close1 = iClose(_Symbol, PERIOD_H4, 1);
            double h4_high2  = iHigh(_Symbol, PERIOD_H4, 2);
            double h4_low2   = iLow(_Symbol, PERIOD_H4, 2);
            
            double candleSizePips = (h4_high1 - h4_low1) / g_pipSize;
            
            if(candleSizePips >= InpMinH4Pips)
            {
               bool isBullSweep = (h4_low1 < h4_low2 && h4_close1 > h4_low2 && h4_high1 <= h4_high2);
               bool isBearSweep = (h4_high1 > h4_high2 && h4_close1 < h4_high2 && h4_low1 >= h4_low2);
               
               // Si H4 hizo un Sweep confirmando a D1 -> ACTIVAR MODO CAZA
               if(isBullSweep && dailyBias == 1) 
               {
                  g_hunting_bias = 1;
                  g_hunting_expiry = TimeCurrent() + (4 * 3600); // 4 horas para encontrar el H1 Run
                  Print(">>> MODO CAZA ALCISTA ACTIVADO en H4 <<<");
               }
               else if(isBearSweep && dailyBias == -1)
               {
                  g_hunting_bias = -1;
                  g_hunting_expiry = TimeCurrent() + (4 * 3600); 
                  Print(">>> MODO CAZA BAJISTA ACTIVADO en H4 <<<");
               }
            }
         }
      }
   }

   // --- FASE 2: GATILLO H1 (El Disparo) ---
   // Solo evaluamos H1 si estamos en "Modo Caza"
   if(g_hunting_bias != 0)
   {
      // Comprobar si el permiso de H4 caducó
      if(TimeCurrent() >= g_hunting_expiry)
      {
         g_hunting_bias = 0;
         return;
      }
      
      datetime currentH1Bar = iTime(_Symbol, PERIOD_H1, 0);
      if(currentH1Bar != g_lastH1Bar)
      {
         g_lastH1Bar = currentH1Bar;
         
         if(HasOpenPosition()) 
         {
            g_hunting_bias = 0; // Ya disparamos
            return;
         }
         
         double h1_high1  = iHigh(_Symbol, PERIOD_H1, 1);
         double h1_low1   = iLow(_Symbol, PERIOD_H1, 1);
         double h1_close1 = iClose(_Symbol, PERIOD_H1, 1);
         double h1_high2  = iHigh(_Symbol, PERIOD_H1, 2);
         double h1_low2   = iLow(_Symbol, PERIOD_H1, 2);
         
         int signal = 0;
         double sl = 0, tp = 0;
         double ask = symInfo.Ask();
         double bid = symInfo.Bid();
         double buffer = InpSpreadBufferPips * g_pipSize;
         
         // Buscamos el RUN en H1 a favor de nuestro bias
         if(g_hunting_bias == 1 && h1_close1 > h1_high2)
         {
            double distTPPips = (h1_high1 - ask) / g_pipSize;
            if(distTPPips >= InpMinH1RunPips)
            {
               signal = 1;
               double structural_sl = h1_low1 - buffer;
               sl = ((ask - structural_sl) / g_pipSize < InpMinH1RunPips) ? ask - (distTPPips * g_pipSize) - buffer : structural_sl;
               
               tp = GetDailyTarget(1);
               // Si el target diario ya se tocó o está muy cerca, anulamos
               if(tp < ask + (10 * g_pipSize)) signal = 0; 
            }
         }
         else if(g_hunting_bias == -1 && h1_close1 < h1_low2)
         {
            double distTPPips = (bid - h1_low1) / g_pipSize;
            if(distTPPips >= InpMinH1RunPips)
            {
               signal = -1;
               double structural_sl = h1_high1 + buffer;
               sl = ((structural_sl - bid) / g_pipSize < InpMinH1RunPips) ? bid + (distTPPips * g_pipSize) + buffer : structural_sl;
               
               tp = GetDailyTarget(-1);
               if(tp > bid - (10 * g_pipSize) || tp == 0) signal = 0;
            }
         }
         
         // Ejecutar si hay señal
         if(signal != 0)
         {
            double entryPrice = (signal == 1) ? ask : bid;
            double lotSize = CalculateLotSize(sl, entryPrice);
            if(lotSize > 0)
            {
               if(signal == 1) trade.Buy(lotSize, _Symbol, ask, sl, tp, "MASTER_RUN_BUY");
               else trade.Sell(lotSize, _Symbol, bid, sl, tp, "MASTER_RUN_SELL");
               
               g_hunting_bias = 0; // Apagar modo caza tras disparar
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop Step 2R                                            |
//+------------------------------------------------------------------+
void ManageTrailingStop_ByRR()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posInfo.SelectByIndex(i))
      {
         if(posInfo.Symbol() == _Symbol && posInfo.Magic() == InpMagic)
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

            if(currentR >= 2)
            {
               double newSL = 0;
               if(posInfo.PositionType() == POSITION_TYPE_BUY)
               {
                  newSL = openPrice + ((currentR - 1) * risk);
                  if(newSL > currentSL + (g_pipSize * 2)) trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
               }
               else if(posInfo.PositionType() == POSITION_TYPE_SELL)
               {
                  newSL = openPrice - ((currentR - 1) * risk);
                  if(newSL < currentSL - (g_pipSize * 2) || currentSL == 0) trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
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