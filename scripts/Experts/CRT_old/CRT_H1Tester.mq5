//+------------------------------------------------------------------+
//|                                              CRT_H1_Tester.mq5   |
//| V8 - Pure H1 Timeframe Test (No Daily Bias, No Trailing Stop)    |
//+------------------------------------------------------------------+
#property copyright "CRT Strategy Tester"
#property version   "8.00"
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
input long     InpMagic            = 110801;  // Magic Number para H1

input group    "=== Ventana Operativa (Hora Broker) ==="
// Rango horario para H1 (ej. sesión de Londres/NY)
input int      InpStartHour        = 9;       // Empieza a operar a esta hora
input int      InpEndHour          = 18;      // Deja de buscar operaciones a esta hora
input int      InpCloseHour        = 22;      // Hora cierre forzado
input int      InpCloseMinute      = 50;

input group    "=== Parámetros SWEEP H1 ==="
input bool     InpEnableSweep      = true;    
input double   InpSweepMinRR       = 1.0;     // No opera si el TP al extremo da menos de 1:1

input group    "=== Parámetros RUN H1 ==="
input bool     InpEnableRun        = true;    
input double   InpMinRunTPPips     = 3.0;     // Pips mínimos de mecha (reducido para H1)
input double   InpMinRunSLPips     = 3.0;     // Pips mínimos de SL estructural (reducido para H1)

input group    "=== Filtros Generales H1 ==="
input double   InpMinPips          = 4.0;     // Tamaño mínimo vela H1 (reducido para H1)
input double   InpSpreadBufferPips = 2.0;     // Respiro del Spread

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

   // 1. Cierre forzado fin de día
   if(dt.hour == InpCloseHour && dt.min >= InpCloseMinute)
   {
      CloseAllPositions();
      return; 
   }

   // 2. Comprobar ventana horaria de entradas
   if(dt.hour < InpStartHour || dt.hour > InpEndHour) return;

   // 3. Evaluar nueva vela H1 (EJECUCIÓN INSTANTÁNEA)
   datetime currentH1Bar = iTime(_Symbol, PERIOD_H1, 0);
   if(currentH1Bar == g_lastH1Bar) return; 
   g_lastH1Bar = currentH1Bar;

   // No abrir si ya tenemos una operación abierta (para no solapar)
   if(HasOpenPosition()) return;

   // 4. Obtener datos de la vela H1 que acaba de cerrar (Índice 1 y 2)
   double high1  = iHigh(_Symbol, PERIOD_H1, 1);
   double low1   = iLow(_Symbol, PERIOD_H1, 1);
   double close1 = iClose(_Symbol, PERIOD_H1, 1);
   double high2  = iHigh(_Symbol, PERIOD_H1, 2);
   double low2   = iLow(_Symbol, PERIOD_H1, 2);
   
   int signal = 0; 
   double sl = 0, tp = 0;
   string comment = "";

   double ask = symInfo.Ask();
   double bid = symInfo.Bid();
   double buffer = InpSpreadBufferPips * g_pipSize;

   // --- LÓGICA SWEEP H1 (Reversión al extremo) ---
   if(InpEnableSweep)
   {
      double candleSizePips = (high1 - low1) / g_pipSize;
      if(candleSizePips >= InpMinPips)
      {
         bool isBullSweep = (low1 < low2 && close1 > low2 && high1 <= high2);
         bool isBearSweep = (high1 > high2 && close1 < high2 && low1 >= low2);

         if(isBullSweep)
         {
            double temp_sl = low1 - buffer;
            double risk = ask - temp_sl;
            double structuralReward = high2 - ask; 
            
            // Evaluamos Ratio (Solo entra si es >= InpSweepMinRR)
            if(structuralReward >= (risk * InpSweepMinRR))
            {
               signal = 1; sl = temp_sl; tp = high2; comment = "H1_SWEEP_BUY";
            }
         }
         else if(isBearSweep)
         {
            double temp_sl = high1 + buffer;
            double risk = temp_sl - bid;
            double structuralReward = bid - low2; 
            
            if(structuralReward >= (risk * InpSweepMinRR))
            {
               signal = -1; sl = temp_sl; tp = low2; comment = "H1_SWEEP_SELL";
            }
         }
      }
   }

   // --- LÓGICA RUN H1 (Continuación para rellenar mecha) ---
   if(InpEnableRun && signal == 0)
   {
      if(close1 > high2) // Alcista
      {
         double distTPPips = (high1 - ask) / g_pipSize;
         if(distTPPips >= InpMinRunTPPips)
         {
            signal = 1;
            tp = high1; // El target siempre es rellenar la mecha de la vela que rompe
            
            double structural_sl = low1 - buffer;
            // Si el SL estructural es muy pequeño, forzamos SL 1:1
            if((ask - structural_sl) / g_pipSize < InpMinRunSLPips) 
            {
               sl = ask - (distTPPips * g_pipSize) - buffer;
               comment = "H1_RUN_BUY_1to1";
            }
            else 
            {
               sl = structural_sl;
               comment = "H1_RUN_BUY_Struct";
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
               comment = "H1_RUN_SELL_1to1";
            }
            else 
            {
               sl = structural_sl;
               comment = "H1_RUN_SELL_Struct";
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