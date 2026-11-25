//+------------------------------------------------------------------+
//|                                      CRT_Run_Volatility_V10.mq5  |
//|               Test de Runs, Fibo y Tamaño del Movimiento (Pts)   |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "10.00"
#property script_show_inputs

input int InpHistoryBars = 1500; // Cantidad de velas a analizar

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
     ENUM_TIMEFRAMES timeframes[] = {PERIOD_W1, PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H4};
     int numTFs = ArraySize(timeframes);

     Print("=====================================================================");
     Print(" INICIANDO ANÁLISIS V10 DE VOLATILIDAD Y RUNS PARA: ", _Symbol);
     Print(" Targets: 127.2%, 161.8%, 200.0% | Medición en PUNTOS del Bróker");
     Print("=====================================================================");

     for(int t = 0; t < numTFs; t++)
       {
          ENUM_TIMEFRAMES curTF = timeframes[t];
          string tfName = EnumToString(curTF);
          
          // Contadores Compras (Bullish)
          int bullTotal = 0, bullFib127 = 0, bullFib161 = 0, bullFib200 = 0, bullLoss = 0;
          double bullSumPts = 0, bullMaxPts = 0, bullMinPts = DBL_MAX;
          
          // Contadores Ventas (Bearish)
          int bearTotal = 0, bearFib127 = 0, bearFib161 = 0, bearFib200 = 0, bearLoss = 0;
          double bearSumPts = 0, bearMaxPts = 0, bearMinPts = DBL_MAX;

          int bars = iBars(_Symbol, curTF);
          int limit = MathMin(bars - 2, InpHistoryBars); 
          
          if(limit <= 0) continue;

          for(int i = limit; i >= 1; i--)
            {
               // 1. Rango Anterior (El que va a ser roto)
               double prevHigh = iHigh(_Symbol, curTF, i+1);
               double prevLow = iLow(_Symbol, curTF, i+1);
               double prevRange = prevHigh - prevLow;
               
               // Calcular el tamaño del rango roto en PUNTOS
               double rangePts = prevRange / _Point;

               // 2. Vela Actual (El Run)
               double curHigh = iHigh(_Symbol, curTF, i);
               double curLow = iLow(_Symbol, curTF, i);
               double curClose = iClose(_Symbol, curTF, i);

               // =================================================================
               // 1. BULLISH RUN (Rompe y Cierra por ENCIMA)
               // =================================================================
               if(curHigh > prevHigh && curClose > prevHigh)
                 {
                    bullTotal++;
                    bullSumPts += rangePts;
                    if(rangePts > bullMaxPts) bullMaxPts = rangePts;
                    if(rangePts < bullMinPts) bullMinPts = rangePts;

                    double stopLoss = curLow; 
                    double target127 = prevHigh + (prevRange * 0.272);
                    double target161 = prevHigh + (prevRange * 0.618);
                    double target200 = prevHigh + (prevRange * 1.000); 

                    bool hit127 = false, hit161 = false, hit200 = false, hitLoss = false;

                    for(int j = i - 1; j >= 0; j--)
                      {
                         double fHigh = iHigh(_Symbol, curTF, j);
                         double fLow  = iLow(_Symbol, curTF, j);

                         if(fLow < stopLoss && !hit127 && !hit161 && !hit200) { hitLoss = true; break; }
                         
                         if(fHigh >= target127 && !hit127) hit127 = true;
                         if(fHigh >= target161 && !hit161) hit161 = true;
                         if(fHigh >= target200 && !hit200) hit200 = true;
                         
                         if(hit200) break; 
                         if(fLow < stopLoss) break;   
                      }
                      
                    if(hit127) bullFib127++;
                    if(hit161) bullFib161++;
                    if(hit200) bullFib200++;
                    if(hitLoss && !hit127) bullLoss++;
                 }

               // =================================================================
               // 2. BEARISH RUN (Rompe y Cierra por DEBAJO)
               // =================================================================
               if(curLow < prevLow && curClose < prevLow)
                 {
                    bearTotal++;
                    bearSumPts += rangePts;
                    if(rangePts > bearMaxPts) bearMaxPts = rangePts;
                    if(rangePts < bearMinPts) bearMinPts = rangePts;

                    double stopLoss = curHigh; 
                    double target127 = prevLow - (prevRange * 0.272);
                    double target161 = prevLow - (prevRange * 0.618);
                    double target200 = prevLow - (prevRange * 1.000); 

                    bool hit127 = false, hit161 = false, hit200 = false, hitLoss = false;

                    for(int j = i - 1; j >= 0; j--)
                      {
                         double fHigh = iHigh(_Symbol, curTF, j);
                         double fLow  = iLow(_Symbol, curTF, j);

                         if(fHigh > stopLoss && !hit127 && !hit161 && !hit200) { hitLoss = true; break; }
                         
                         if(fLow <= target127 && !hit127) hit127 = true;
                         if(fLow <= target161 && !hit161) hit161 = true;
                         if(fLow <= target200 && !hit200) hit200 = true;
                         
                         if(hit200) break; 
                         if(fHigh > stopLoss) break;   
                      }
                      
                    if(hit127) bearFib127++;
                    if(hit161) bearFib161++;
                    if(hit200) bearFib200++;
                    if(hitLoss && !hit127) bearLoss++;
                 }
            }

          // --- IMPRIMIR RESULTADOS ---
          Print("--- TIMEFRAME: ", tfName, " ---");
          
          if(bullTotal > 0)
            {
               double avgPts = bullSumPts / bullTotal;
               Print("🟢 COMPRAS (", bullTotal, ") | Win 161.8%: ", DoubleToString((double)bullFib161/bullTotal*100, 1), "% | Win 200%: ", DoubleToString((double)bullFib200/bullTotal*100, 1), "%");
               Print("    RANGO ROTO -> Avg: ", DoubleToString(avgPts, 0), " pts | Min: ", DoubleToString(bullMinPts, 0), " pts | Max: ", DoubleToString(bullMaxPts, 0), " pts");
            }
                   
          if(bearTotal > 0)
            {
               double avgPts = bearSumPts / bearTotal;
               Print("🔴 VENTAS  (", bearTotal, ") | Win 161.8%: ", DoubleToString((double)bearFib161/bearTotal*100, 1), "% | Win 200%: ", DoubleToString((double)bearFib200/bearTotal*100, 1), "%");
               Print("    RANGO ROTO -> Avg: ", DoubleToString(avgPts, 0), " pts | Min: ", DoubleToString(bearMinPts, 0), " pts | Max: ", DoubleToString(bearMaxPts, 0), " pts");
            }
          Print("---------------------------------------");
       }
     Print("================= FIN DEL ANÁLISIS =====================");
  }
