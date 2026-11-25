//+------------------------------------------------------------------+
//|                                              CRT_AutoBot_v4.mq5  |
//|    EA Avanzado: Gestión Dinámica, Lotes % y TP Extendido en Runs |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "4.00"

#include <Trade\Trade.mqh>

//--- Inputs del Bot
input ENUM_TIMEFRAMES InpTimeFrame   = PERIOD_H4;     // Temporalidad
input double          InpRiskPercent = 0.5;           // Riesgo % por operación
input double          InpMinPips     = 5.0;           // Filtro de tamaño de Rango (Pips)
input bool            InpTradeSweeps = true;          // ¿Operar Sweeps (Reversiones)?
input bool            InpTradeRuns   = true;          // ¿Operar Runs (Continuaciones)?
input ulong           InpMagicNumber = 123456;        // Magic Number

CTrade trade;
datetime lastBarTime;
double pipSize;

//+------------------------------------------------------------------+
int OnInit()
  {
     trade.SetExpertMagicNumber(InpMagicNumber);
     lastBarTime = iTime(_Symbol, InpTimeFrame, 0);
     pipSize = (_Digits == 5 || _Digits == 3) ? _Point * 10 : _Point;
     Print("🤖 CRT AutoBot V4 | Riesgo: ", InpRiskPercent, "% | Filtro: ", InpMinPips, " pips | TP Runs Extendido (Max/Min)");
     return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
double CalculateLotSize(double slDistancePrice)
  {
     if(slDistancePrice <= 0) return 0;
     double balance = AccountInfoDouble(ACCOUNT_BALANCE);
     double riskMoney = balance * (InpRiskPercent / 100.0); 
     
     double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
     double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
     if(tickSize == 0 || tickValue == 0) return 0;
     
     double riskPerLot = (slDistancePrice / tickSize) * tickValue; 
     if(riskPerLot <= 0) return 0;
     
     double lots = riskMoney / riskPerLot; 
     
     double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
     double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
     double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
     
     lots = MathRound(lots / step) * step;
     if(lots < minLot) lots = minLot;
     if(lots > maxLot) lots = maxLot;
     
     return lots;
  }

//+------------------------------------------------------------------+
void CloseAllPositions()
  {
     for(int i = PositionsTotal() - 1; i >= 0; i--)
       {
          ulong ticket = PositionGetTicket(i);
          if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
               trade.PositionClose(ticket);
            }
       }
  }

//+------------------------------------------------------------------+
void OnTick()
  {
     datetime currentBarTime = iTime(_Symbol, InpTimeFrame, 0);
     if(currentBarTime == lastBarTime) return; 
     lastBarTime = currentBarTime;

     int currentPosType = -1; 
     if(PositionsTotal() > 0)
       {
          for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
               ulong ticket = PositionGetTicket(i);
               if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
                 {
                    currentPosType = (int)PositionGetInteger(POSITION_TYPE);
                    break;
                 }
            }
       }

     // Velas Clave
     double prevHigh = iHigh(_Symbol, InpTimeFrame, 2); 
     double prevLow  = iLow(_Symbol, InpTimeFrame, 2);
     double prevRange = prevHigh - prevLow;
     
     // Filtro de Pips
     if(prevRange < (InpMinPips * pipSize)) return;

     double curHigh  = iHigh(_Symbol, InpTimeFrame, 1); 
     double curLow   = iLow(_Symbol, InpTimeFrame, 1);
     double curClose = iClose(_Symbol, InpTimeFrame, 1);
     
     double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
     double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

     int signalType = -1; 
     string signalName = "";
     double sl = 0, tp = 0;

     // =================================================================
     // LÓGICA DE SWEEPS
     // =================================================================
     if(InpTradeSweeps)
       {
          if(curHigh > prevHigh && curClose < prevHigh)
            {
               signalType = 1; 
               signalName = "Bearish Sweep";
               sl = curHigh; 
               tp = prevHigh - (prevRange * 0.5); 
            }
          else if(curLow < prevLow && curClose > prevLow)
            {
               signalType = 0;
               signalName = "Bullish Sweep";
               sl = curLow;
               tp = prevLow + (prevRange * 0.5);
            }
       }

     // =================================================================
     // LÓGICA DE RUNS (TP Extendido: Extremo de mecha o Fibo 161.8%)
     // =================================================================
     if(signalType == -1 && InpTradeRuns)
       {
          if(curLow < prevLow && curClose < prevLow)
            {
               signalType = 1;
               signalName = "Bearish Run";
               sl = curHigh;
               double fiboTP = prevLow - (prevRange * 0.618); 
               // MathMin: Elegimos el precio MÁS BAJO (el objetivo más profundo y ambicioso)
               tp = MathMin(fiboTP, curLow); 
            }
          else if(curHigh > prevHigh && curClose > prevHigh)
            {
               signalType = 0;
               signalName = "Bullish Run";
               sl = curLow;
               double fiboTP = prevHigh + (prevRange * 0.618); 
               // MathMax: Elegimos el precio MÁS ALTO (el objetivo más alto y ambicioso)
               tp = MathMax(fiboTP, curHigh); 
            }
       }

     // =================================================================
     // GESTIÓN DINÁMICA
     // =================================================================
     if(signalType != -1) 
       {
          if(currentPosType != -1)
            {
               if(currentPosType == signalType) return;
               Print("🔄 REVERSIÓN DINÁMICA (", signalName, ")! Cerrando posición...");
               CloseAllPositions();
            }

          if(signalType == 0) // COMPRA
            {
               double slDist = ask - sl;
               double lots = CalculateLotSize(slDist);
               if(ask < tp && lots > 0)
                 {
                    trade.Buy(lots, _Symbol, ask, sl, tp, signalName);
                    Print("📈 ", signalName, " | Lotes: ", DoubleToString(lots, 2));
                 }
               else { Print("⚠️ Operación omitida: El precio actual ya alcanzó o superó el Take Profit proyectado."); }
            }
          else if(signalType == 1) // VENTA
            {
               double slDist = sl - bid;
               double lots = CalculateLotSize(slDist);
               if(bid > tp && lots > 0)
                 {
                    trade.Sell(lots, _Symbol, bid, sl, tp, signalName);
                    Print("📉 ", signalName, " | Lotes: ", DoubleToString(lots, 2));
                 }
               else { Print("⚠️ Operación omitida: El precio actual ya alcanzó o superó el Take Profit proyectado."); }
            }
       }
  }
//+------------------------------------------------------------------+