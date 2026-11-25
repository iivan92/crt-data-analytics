//+------------------------------------------------------------------+
//|                                     CRT_Sweep_Analyzer_V5.mq5    |
//|         Bias All-in-One: MN1 a H4 con Fibo 38, 50, 61 y 100      |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "5.00"
#property script_show_inputs

//--- Input parameters
input int InpHistoryBars = 1500; // Cantidad máxima de velas a analizar por Timeframe

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
     // Array con todos los timeframes a testear
     ENUM_TIMEFRAMES timeframes[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H4};
     int numTFs = ArraySize(timeframes);

     Print("=====================================================================");
     Print(" INICIANDO ANÁLISIS V5 (INCLUYE 100% RANGO) PARA: ", _Symbol);
     Print("=====================================================================");

     for(int t = 0; t < numTFs; t++)
       {
          ENUM_TIMEFRAMES curTF = timeframes[t];
          string tfName = EnumToString(curTF);
          
          // Contadores Bearish
          int bearTotal = 0, bearFib38 = 0, bearFib50 = 0, bearFib61 = 0, bearFib100 = 0, bearLoss = 0;
          // Contadores Bullish
          int bullTotal = 0, bullFib38 = 0, bullFib50 = 0, bullFib61 = 0, bullFib100 = 0, bullLoss = 0;

          int bars = iBars(_Symbol, curTF);
          int limit = MathMin(bars - 2, InpHistoryBars); 
          
          if(limit <= 0) continue;

          for(int i = limit; i >= 1; i--)
            {
               // Rango Previo
               double prevHigh = iHigh(_Symbol, curTF, i+1);
               double prevLow = iLow(_Symbol, curTF, i+1);
               double prevRange = prevHigh - prevLow;

               // Vela de Barrido
               double curHigh = iHigh(_Symbol, curTF, i);
               double curLow = iLow(_Symbol, curTF, i);
               double curClose = iClose(_Symbol, curTF, i);

               // -----------------------------------------------------------------
               // 1. BEARISH SWEEP (Barrido de Máximo)
               // -----------------------------------------------------------------
               if(curHigh > prevHigh && curClose < prevHigh)
                 {
                    bearTotal++;
                    double stopLoss = curHigh; 
                    double target38 = prevHigh - (prevRange * 0.382);
                    double target50 = prevHigh - (prevRange * 0.500);
                    double target61 = prevHigh - (prevRange * 0.618);
                    double target100 = prevLow; // El 100% es el mínimo anterior exacto

                    bool hit38 = false, hit50 = false, hit61 = false, hit100 = false, hitLoss = false;

                    for(int j = i - 1; j >= 0; j--)
                      {
                         double fHigh = iHigh(_Symbol, curTF, j);
                         double fLow  = iLow(_Symbol, curTF, j);

                         if(fHigh > stopLoss && !hit38 && !hit50 && !hit61 && !hit100) { hitLoss = true; break; }
                         
                         if(fLow <= target38 && !hit38) hit38 = true;
                         if(fLow <= target50 && !hit50) hit50 = true;
                         if(fLow <= target61 && !hit61) hit61 = true;
                         if(fLow <= target100 && !hit100) hit100 = true;
                         
                         if(hit100) break; // Completó el rango entero (Full Transfer)
                         if(fHigh > stopLoss) break;   
                      }
                      
                    if(hit38) bearFib38++;
                    if(hit50) bearFib50++;
                    if(hit61) bearFib61++;
                    if(hit100) bearFib100++;
                    if(hitLoss && !hit38) bearLoss++;
                 }

               // -----------------------------------------------------------------
               // 2. BULLISH SWEEP (Barrido de Mínimo)
               // -----------------------------------------------------------------
               if(curLow < prevLow && curClose > prevLow)
                 {
                    bullTotal++;
                    double stopLoss = curLow; 
                    double target38 = prevLow + (prevRange * 0.382);
                    double target50 = prevLow + (prevRange * 0.500);
                    double target61 = prevLow + (prevRange * 0.618);
                    double target100 = prevHigh; // El 100% es el máximo anterior exacto

                    bool hit38 = false, hit50 = false, hit61 = false, hit100 = false, hitLoss = false;

                    for(int j = i - 1; j >= 0; j--)
                      {
                         double fHigh = iHigh(_Symbol, curTF, j);
                         double fLow  = iLow(_Symbol, curTF, j);

                         if(fLow < stopLoss && !hit38 && !hit50 && !hit61 && !hit100) { hitLoss = true; break; }
                         
                         if(fHigh >= target38 && !hit38) hit38 = true;
                         if(fHigh >= target50 && !hit50) hit50 = true;
                         if(fHigh >= target61 && !hit61) hit61 = true;
                         if(fHigh >= target100 && !hit100) hit100 = true;
                         
                         if(hit100) break; // Completó el rango entero (Full Transfer)
                         if(fLow < stopLoss) break;   
                      }
                      
                    if(hit38) bullFib38++;
                    if(hit50) bullFib50++;
                    if(hit61) bullFib61++;
                    if(hit100) bullFib100++;
                    if(hitLoss && !hit38) bullLoss++;
                 }
            }

          // --- IMPRIMIR ESTADÍSTICAS POR TIMEFRAME ---
          Print("--- ", tfName, " ---");
          
          if(bearTotal > 0)
            {
               Print("🔴 VENTAS (", bearTotal, " sweeps) | ",
                     "F38: ", DoubleToString((double)bearFib38/bearTotal*100, 1), "% | ",
                     "F50: ", DoubleToString((double)bearFib50/bearTotal*100, 1), "% | ",
                     "F61: ", DoubleToString((double)bearFib61/bearTotal*100, 1), "% | ",
                     "F100: ", DoubleToString((double)bearFib100/bearTotal*100, 1), "% | ",
                     "Loss: ", DoubleToString((double)bearLoss/bearTotal*100, 1), "%");
            }
                   
          if(bullTotal > 0)
            {
               Print("🟢 COMPRAS (", bullTotal, " sweeps) | ",
                     "F38: ", DoubleToString((double)bullFib38/bullTotal*100, 1), "% | ",
                     "F50: ", DoubleToString((double)bullFib50/bullTotal*100, 1), "% | ",
                     "F61: ", DoubleToString((double)bullFib61/bullTotal*100, 1), "% | ",
                     "F100: ", DoubleToString((double)bullFib100/bullTotal*100, 1), "% | ",
                     "Loss: ", DoubleToString((double)bullLoss/bullTotal*100, 1), "%");
            }
       }
     Print("================= FIN DEL ANÁLISIS =================");
  }