//+------------------------------------------------------------------+
//|                                     CRT_Fractal_Sweep_V15.mq5    |
//| V15 - Structural H4 Range TP + Ratio Cap + TS/BE                 |
//+------------------------------------------------------------------+
#property copyright "CRT Strategy Tester"
#property version   "15.00"
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
input long     InpMagic            = 150801;  

input group    "=== Horario Operativo ==="
input int      InpStartHour        = 8;       
input int      InpEndHour          = 18;      
input int      InpCloseHour        = 22;      
input int      InpCloseMinute      = 50;

input group    "=== Gestión Estructural de Salida ==="
input double   InpMinSLPips        = 5.0;     // SL mínimo
input double   InpTargetRR         = 2.0;     // Ratio Límite Máximo (Si la vela H4 es gigante)

input group    "=== Break Even (BE) ==="
input bool     InpEnableBE         = true;    
input double   InpBE_ActivationRR  = 1.0;     
input double   InpBE_BufferPips    = 0.5;     

input group    "=== Step Trailing Stop ==="
input bool     InpEnableTS         = true;    
input double   InpTS_ActivationRR  = 2.0;     

input group    "=== Filtros del Patrón ==="
input double   InpMinPipsH1        = 3.0;     
input double   InpSpreadBufferPips = 2.0;     

//--- Variables Globales
datetime       g_lastH1Bar = 0;
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

   if(dt.hour == InpCloseHour && dt.min >= InpCloseMinute)
   {
      CloseAllPositions();
      return; 
   }

   if(HasOpenPosition()) ManageTradeExit();

   if(dt.hour < InpStartHour || dt.hour > InpEndHour) return;

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
   string comment = "";

   // --- LÓGICA ALCISTA ---
   if(isH1BullSweep)
   {
      if(h4_low0 < h4_low1 && ask > h4_low1)
      {
         double entryPrice = ask;
         double temp_sl = h4_low0 - buffer;
         double currentRiskPips = (entryPrice - temp_sl) / g_pipSize;
         
         // 1. Forzar SL mínimo
         if(currentRiskPips < InpMinSLPips) temp_sl = entryPrice - (InpMinSLPips * g_pipSize);
         
         double risk = entryPrice - temp_sl;
         double struct_tp = h4_high1; // Cierre del rango H4
         double struct_reward = struct_tp - entryPrice;
         
         // 2. Filtro Vela Pequeña: Si ir al rango no da ni 1:1, ignorar
         if(struct_reward >= risk)
         {
            signal = 1; sl = temp_sl;
            
            // 3. Filtro Vela Grande: Si el rango da más que nuestro Target Límite, lo capamos
            double limit_reward = risk * InpTargetRR;
            if(struct_reward > limit_reward) {
               tp = entryPrice + limit_reward;
               comment = "V15_BUY_RatioCap";
            } else {
               tp = struct_tp;
               comment = "V15_BUY_Range";
            }
         }
      }
   }
   
   // --- LÓGICA BAJISTA ---
   else if(isH1BearSweep)
   {
      if(h4_high0 > h4_high1 && bid < h4_high1)
      {
         double entryPrice = bid;
         double temp_sl = h4_high0 + buffer;
         double currentRiskPips = (temp_sl - entryPrice) / g_pipSize;
         
         if(currentRiskPips < InpMinSLPips) temp_sl = entryPrice + (InpMinSLPips * g_pipSize);
         
         double risk = temp_sl - entryPrice;
         double struct_tp = h4_low1; // Cierre del rango H4
         double struct_reward = entryPrice - struct_tp;
         
         if(struct_reward >= risk)
         {
            signal = -1; sl = temp_sl;
            
            double limit_reward = risk * InpTargetRR;
            if(struct_reward > limit_reward) {
               tp = entryPrice - limit_reward;
               comment = "V15_SELL_RatioCap";
            } else {
               tp = struct_tp;
               comment = "V15_SELL_Range";
            }
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
         if(signal == 1) trade.Buy(lotSize, _Symbol, ask, sl, tp, comment);
         else trade.Sell(lotSize, _Symbol, bid, sl, tp, comment);
      }
   }
}

//+------------------------------------------------------------------+
//| Gestión Activa (Break Even y Trailing Stop)                      |
//+------------------------------------------------------------------+
void ManageTradeExit()
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
            double currentR_float = currentProfit / risk; 
            int currentR_int = (int)MathFloor(currentR_float); 

            double newSL = currentSL;
            bool modify = false;
            double be_buffer = InpBE_BufferPips * g_pipSize;

            if(posInfo.PositionType() == POSITION_TYPE_BUY)
            {
               if(InpEnableBE && currentR_float >= InpBE_ActivationRR && currentSL < openPrice)
               {
                  newSL = openPrice + be_buffer;
                  modify = true;
               }
               else if(InpEnableTS && currentR_int >= InpTS_ActivationRR)
               {
                  double tempSL = openPrice + ((currentR_int - 1) * risk);
                  if(tempSL > currentSL + (g_pipSize * 1)) 
                  {
                     newSL = tempSL;
                     modify = true;
                  }
               }
            }
            else if(posInfo.PositionType() == POSITION_TYPE_SELL)
            {
               if(InpEnableBE && currentR_float >= InpBE_ActivationRR && (currentSL > openPrice || currentSL == 0))
               {
                  newSL = openPrice - be_buffer;
                  modify = true;
               }
               else if(InpEnableTS && currentR_int >= InpTS_ActivationRR)
               {
                  double tempSL = openPrice - ((currentR_int - 1) * risk);
                  if(tempSL < currentSL - (g_pipSize * 1) || currentSL == 0) 
                  {
                     newSL = tempSL;
                     modify = true;
                  }
               }
            }

            if(modify) trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                          |
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