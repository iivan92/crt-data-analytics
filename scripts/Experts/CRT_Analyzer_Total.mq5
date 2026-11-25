//+------------------------------------------------------------------+
//|                                     CRT_Master_Analyzer_V12.mq5  |
//|    Simulación 100% del EA (TP 50% Sweeps + Gestión Dinámica)     |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "12.00"
#property script_show_inputs

input int    InpHistoryBars = 2000;  // Cantidad de velas a analizar
input double InpMinPips     = 5.0;   // Filtro: Tamaño mínimo del rango (Pips)

//+------------------------------------------------------------------+
void OnStart()
  {
     ENUM_TIMEFRAMES timeframes[] = {PERIOD_W1, PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H4};
     int numTFs = ArraySize(timeframes);
     
     double pipSize = (_Digits == 5 || _Digits == 3) ? _Point * 10 : _Point;

     Print("=====================================================================");
     Print(" INICIANDO ANALIZADOR MAESTRO V12 (Simulación de Bot) PARA: ", _Symbol);
     Print(" Filtro > ", InpMinPips, " pips | TP Sweeps: 50% | TP Runs: 161.8% o Mecha");
     Print(" Incluye Cierre Dinámico si aparece un patrón contrario.");
     Print("=====================================================================");

     for(int t = 0; t < numTFs; t++)
       {
          ENUM_TIMEFRAMES curTF = timeframes[t];
          string tfName = EnumToString(curTF);
          
          // Contadores
          int bullSweepTotal = 0, bullSweepWin = 0, bullSweepSL = 0, bullSweepRev = 0;
          int bearSweepTotal = 0, bearSweepWin = 0, bearSweepSL = 0, bearSweepRev = 0;
          
          int bullRunTotal = 0, bullRunWin = 0, bullRunSL = 0, bullRunRev = 0;
          int bearRunTotal = 0, bearRunWin = 0, bearRunSL = 0, bearRunRev = 0;

          int bars = iBars(_Symbol, curTF);
          int limit = MathMin(bars - 2, InpHistoryBars); 
          
          if(limit <= 0) continue;

          for(int i = limit; i >= 1; i--)
            {
               double prevHigh = iHigh(_Symbol, curTF, i+1);
               double prevLow  = iLow(_Symbol, curTF, i+1);
               double prevRange = prevHigh - prevLow;
               
               if(prevRange < (InpMinPips * pipSize)) continue;

               double curHigh  = iHigh(_Symbol, curTF, i);
               double curLow   = iLow(_Symbol, curTF, i);
               double curClose = iClose(_Symbol, curTF, i);

               int signalType = -1; // 0: Bull Sweep, 1: Bear Sweep, 2: Bull Run, 3: Bear Run
               double sl = 0, tp = 0;
               bool isBuy = false;

               // --- LÓGICA DE SWEEPS ---
               if(curHigh > prevHigh && curClose < prevHigh)
                 {
                    signalType = 1; isBuy = false; sl = curHigh;
                    tp = prevHigh - (prevRange * 0.500); // TP AL 50%
                    bearSweepTotal++;
                 }
               else if(curLow < prevLow && curClose > prevLow)
                 {
                    signalType = 0; isBuy = true; sl = curLow;
                    tp = prevLow + (prevRange * 0.500); // TP AL 50%
                    bullSweepTotal++;
                 }
               // --- LÓGICA DE RUNS ---
               else if(curHigh > prevHigh && curClose > prevHigh)
                 {
                    signalType = 2; isBuy = true; sl = curLow;
                    double fibo = prevHigh + (prevRange * 0.618);
                    tp = MathMax(fibo, curHigh); 
                    bullRunTotal++;
                 }
               else if(curLow < prevLow && curClose < prevLow)
                 {
                    signalType = 3; isBuy = false; sl = curHigh;
                    double fibo = prevLow - (prevRange * 0.618);
                    tp = MathMin(fibo, curLow); 
                    bearRunTotal++;
                 }

               // --- TRACKING DEL FUTURO Y GESTIÓN DINÁMICA ---
               if(signalType != -1)
                 {
                    bool hitTP = false, hitSL = false, hitRev = false;

                    for(int j = i - 1; j >= 0; j--)
                      {
                         double fHigh = iHigh(_Symbol, curTF, j);
                         double fLow  = iLow(_Symbol, curTF, j);
                         double fClose = iClose(_Symbol, curTF, j);
                         
                         // Datos de la vela anterior a 'j' para evaluar patrones contrarios
                         double pjHigh = iHigh(_Symbol, curTF, j+1);
                         double pjLow  = iLow(_Symbol, curTF, j+1);
                         double pjRange = pjHigh - pjLow;

                         if(isBuy) // ESTAMOS EN COMPRA
                           {
                              if(fLow < sl) { hitSL = true; break; }
                              if(fHigh >= tp) { hitTP = true; break; }
                              
                              // ¿Aparece un patrón bajista (Bear Sweep o Bear Run) que nos corte?
                              if(pjRange >= (InpMinPips * pipSize))
                                {
                                   if(fHigh > pjHigh && fClose < pjHigh) { hitRev = true; break; } // Bear Sweep
                                   if(fLow < pjLow && fClose < pjLow)    { hitRev = true; break; } // Bear Run
                                }
                           }
                         else // ESTAMOS EN VENTA
                           {
                              if(fHigh > sl) { hitSL = true; break; }
                              if(fLow <= tp) { hitTP = true; break; }
                              
                              // ¿Aparece un patrón alcista (Bull Sweep o Bull Run) que nos corte?
                              if(pjRange >= (InpMinPips * pipSize))
                                {
                                   if(fLow < pjLow && fClose > pjLow) { hitRev = true; break; } // Bull Sweep
                                   if(fHigh > pjHigh && fClose > pjHigh) { hitRev = true; break; } // Bull Run
                                }
                           }
                      }
                      
                    // REGISTRO DE RESULTADOS
                    if(hitTP)
                      {
                         if(signalType == 0) bullSweepWin++; else if(signalType == 1) bearSweepWin++;
                         else if(signalType == 2) bullRunWin++; else if(signalType == 3) bearRunWin++;
                      }
                    else if(hitRev)
                      {
                         if(signalType == 0) bullSweepRev++; else if(signalType == 1) bearSweepRev++;
                         else if(signalType == 2) bullRunRev++; else if(signalType == 3) bearRunRev++;
                      }
                    else if(hitSL || (!hitTP && !hitRev)) // SL por mecha o fin de historial
                      {
                         if(signalType == 0) bullSweepSL++; else if(signalType == 1) bearSweepSL++;
                         else if(signalType == 2) bullRunSL++; else if(signalType == 3) bearRunSL++;
                      }
                 }
            }

          // --- IMPRIMIR RESULTADOS ---
          Print("--- TIMEFRAME: ", tfName, " ---");
          
          if(bullSweepTotal > 0) Print("🟢 BULL SWEEP (Compra) | T: ", bullSweepTotal, " | WIN: ", DoubleToString((double)bullSweepWin/bullSweepTotal*100, 1), "% | Cut-REV: ", DoubleToString((double)bullSweepRev/bullSweepTotal*100, 1), "% | SL: ", DoubleToString((double)bullSweepSL/bullSweepTotal*100, 1), "%");
          if(bearSweepTotal > 0) Print("🔴 BEAR SWEEP (Venta)  | T: ", bearSweepTotal, " | WIN: ", DoubleToString((double)bearSweepWin/bearSweepTotal*100, 1), "% | Cut-REV: ", DoubleToString((double)bearSweepRev/bearSweepTotal*100, 1), "% | SL: ", DoubleToString((double)bearSweepSL/bearSweepTotal*100, 1), "%");
          
          if(bullRunTotal > 0)   Print("🚀 BULL RUN   (Compra) | T: ", bullRunTotal,   " | WIN: ", DoubleToString((double)bullRunWin/bullRunTotal*100, 1), "% | Cut-REV: ", DoubleToString((double)bullRunRev/bullRunTotal*100, 1), "% | SL: ", DoubleToString((double)bullRunSL/bullRunTotal*100, 1), "%");
          if(bearRunTotal > 0)   Print("☄️ BEAR RUN   (Venta)  | T: ", bearRunTotal,   " | WIN: ", DoubleToString((double)bearRunWin/bearRunTotal*100, 1), "% | Cut-REV: ", DoubleToString((double)bearRunRev/bearRunTotal*100, 1), "% | SL: ", DoubleToString((double)bearRunSL/bearRunTotal*100, 1), "%");
          Print("---------------------------------------");
       }
     Print("================= FIN DEL ANÁLISIS MAESTRO V12 =================");
  }