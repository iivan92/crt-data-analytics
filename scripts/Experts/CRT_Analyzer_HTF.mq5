//+------------------------------------------------------------------+
//|                               CRT_Matrix_Bias_Analyzer_V5.mq5    |
//|         Análisis Condicional con Línea Base (Baseline) LTF       |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "5.00"
#property script_show_inputs

input int InpHistoryBars = 2000; // Velas a analizar en LTF

struct TFPair {
   ENUM_TIMEFRAMES htf;
   ENUM_TIMEFRAMES ltf;
};

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
     // Definimos las combinaciones que queremos estudiar
     TFPair pairs[] = {
        {PERIOD_MN1, PERIOD_W1},
        {PERIOD_MN1, PERIOD_D1},
        {PERIOD_MN1, PERIOD_H12},
        {PERIOD_MN1, PERIOD_H8},
        {PERIOD_MN1, PERIOD_H4},
        {PERIOD_W1, PERIOD_D1},
        {PERIOD_W1, PERIOD_H12},
        {PERIOD_W1, PERIOD_H8},
        {PERIOD_W1, PERIOD_H4},
        {PERIOD_D1, PERIOD_H12},
        {PERIOD_D1, PERIOD_H8},
        {PERIOD_D1, PERIOD_H4}
     };
     
     int numPairs = ArraySize(pairs);

     Print("=====================================================================");
     Print(" INICIANDO MATRIZ CONDICIONAL (HTF Sweep/RUN -> LTF) PARA: ", _Symbol);
     Print(" Incluyendo Línea Base (Baseline) del Timeframe Menor (LTF)");
     Print("=====================================================================");

     for(int p = 0; p < numPairs; p++)
       {
          ENUM_TIMEFRAMES HTF = pairs[p].htf;
          ENUM_TIMEFRAMES LTF = pairs[p].ltf;
          
          string htfName = EnumToString(HTF);
          string ltfName = EnumToString(LTF);
          
          // Contadores Globales / Baseline (Sin influencia del HTF)
          int baseBearTotal = 0, baseBearF50 = 0, baseBearF100 = 0, baseBearLoss = 0;
          int baseBullTotal = 0, baseBullF50 = 0, baseBullF100 = 0, baseBullLoss = 0;

          // Contadores Alineados (A favor del HTF)
          int alignBearTotal = 0, alignBearF50 = 0, alignBearF100 = 0, alignBearLoss = 0;
          int alignBullTotal = 0, alignBullF50 = 0, alignBullF100 = 0, alignBullLoss = 0;
          
          // Contadores Counter (En contra del HTF)
          int counterBearTotal = 0, counterBearF50 = 0, counterBearF100 = 0, counterBearLoss = 0;
          int counterBullTotal = 0, counterBullF50 = 0, counterBullF100 = 0, counterBullLoss = 0;
          
          // Contadores Neutrales (HTF sin rango activo ni RUN)
          int neutralBearTotal = 0, neutralBearF50 = 0, neutralBearF100 = 0, neutralBearLoss = 0;
          int neutralBullTotal = 0, neutralBullF50 = 0, neutralBullF100 = 0, neutralBullLoss = 0;

          int bars = iBars(_Symbol, LTF);
          int limit = MathMin(bars - 2, InpHistoryBars); 
          if(limit <= 0) continue;

          for(int i = limit; i >= 1; i--)
            {
               // 1. Detección del patrón Sweep en LTF
               double prevHigh = iHigh(_Symbol, LTF, i+1);
               double prevLow  = iLow(_Symbol, LTF, i+1);
               double prevRange = prevHigh - prevLow;
               
               double curHigh  = iHigh(_Symbol, LTF, i);
               double curLow   = iLow(_Symbol, LTF, i);
               double curClose = iClose(_Symbol, LTF, i);
               
               bool isLtfBearSweep = (curHigh > prevHigh && curClose < prevHigh);
               bool isLtfBullSweep = (curLow < prevLow && curClose > prevLow);
               
               if(!isLtfBearSweep && !isLtfBullSweep) continue; // No hay setup en LTF
               
               // 2. Obtener el Bias del HTF en este momento exacto (Sweep o RUN)
               datetime ltfTime = iTime(_Symbol, LTF, i);
               int htfBias = GetActiveHTFBias(_Symbol, HTF, ltfTime);
               
               // 3. Proyección de resultados LTF
               bool hit50 = false, hit100 = false, hitLoss = false;
               
               if(isLtfBearSweep)
                 {
                    double stopLoss = curHigh; 
                    double target50 = prevHigh - (prevRange * 0.500);
                    double target100 = prevLow;
                    
                    for(int j = i - 1; j >= 0; j--)
                      {
                         double fHigh = iHigh(_Symbol, LTF, j);
                         double fLow  = iLow(_Symbol, LTF, j);
                         
                         if(fHigh > stopLoss && !hit50 && !hit100) { hitLoss = true; break; }
                         if(fLow <= target50 && !hit50) hit50 = true;
                         if(fLow <= target100 && !hit100) { hit100 = true; break; }
                         if(fHigh > stopLoss) break;
                      }
                      
                    // --- SUMAR A LA LÍNEA BASE (GLOBAL) ---
                    baseBearTotal++;
                    if(hit50) baseBearF50++;
                    if(hit100) baseBearF100++;
                    if(hitLoss && !hit50) baseBearLoss++;
                      
                    // --- SUMAR A LA ESTADÍSTICA CONDICIONAL ---
                    if(htfBias == -1) // ALINEADO
                      {
                         alignBearTotal++;
                         if(hit50) alignBearF50++;
                         if(hit100) alignBearF100++;
                         if(hitLoss && !hit50) alignBearLoss++;
                      }
                    else if(htfBias == 1) // COUNTER
                      {
                         counterBearTotal++;
                         if(hit50) counterBearF50++;
                         if(hit100) counterBearF100++;
                         if(hitLoss && !hit50) counterBearLoss++;
                      }
                    else // NEUTRAL
                      {
                         neutralBearTotal++;
                         if(hit50) neutralBearF50++;
                         if(hit100) neutralBearF100++;
                         if(hitLoss && !hit50) neutralBearLoss++;
                      }
                 }
                 
               if(isLtfBullSweep)
                 {
                    double stopLoss = curLow;
                    double target50 = prevLow + (prevRange * 0.500);
                    double target100 = prevHigh;
                    
                    for(int j = i - 1; j >= 0; j--)
                      {
                         double fHigh = iHigh(_Symbol, LTF, j);
                         double fLow  = iLow(_Symbol, LTF, j);
                         
                         if(fLow < stopLoss && !hit50 && !hit100) { hitLoss = true; break; }
                         if(fHigh >= target50 && !hit50) hit50 = true;
                         if(fHigh >= target100 && !hit100) { hit100 = true; break; }
                         if(fLow < stopLoss) break;
                      }
                      
                    // --- SUMAR A LA LÍNEA BASE (GLOBAL) ---
                    baseBullTotal++;
                    if(hit50) baseBullF50++;
                    if(hit100) baseBullF100++;
                    if(hitLoss && !hit50) baseBullLoss++;
                      
                    // --- SUMAR A LA ESTADÍSTICA CONDICIONAL ---
                    if(htfBias == 1) // ALINEADO
                      {
                         alignBullTotal++;
                         if(hit50) alignBullF50++;
                         if(hit100) alignBullF100++;
                         if(hitLoss && !hit50) alignBullLoss++;
                      }
                    else if(htfBias == -1) // COUNTER
                      {
                         counterBullTotal++;
                         if(hit50) counterBullF50++;
                         if(hit100) counterBullF100++;
                         if(hitLoss && !hit50) counterBullLoss++;
                      }
                    else // NEUTRAL
                      {
                         neutralBullTotal++;
                         if(hit50) neutralBullF50++;
                         if(hit100) neutralBullF100++;
                         if(hitLoss && !hit50) neutralBullLoss++;
                      }
                 }
            }

          // --- IMPRIMIR RESULTADOS ---
          Print("--- ANÁLISIS: ", ltfName, " INFLUIDO POR ", htfName, " ---");
          
          // Imprimir Ventas
          if(baseBearTotal > 0)
             Print("🌐 BASELINE LTF | 🔴 VENTAS (", baseBearTotal, ") | F50: ", DoubleToString((double)baseBearF50/baseBearTotal*100, 1), "% | F100: ", DoubleToString((double)baseBearF100/baseBearTotal*100, 1), "% | Loss: ", DoubleToString((double)baseBearLoss/baseBearTotal*100, 1), "%");
          if(alignBearTotal > 0)
             Print("✅ ALINEADO HTF | 🔴 VENTAS (", alignBearTotal, ") | F50: ", DoubleToString((double)alignBearF50/alignBearTotal*100, 1), "% | F100: ", DoubleToString((double)alignBearF100/alignBearTotal*100, 1), "% | Loss: ", DoubleToString((double)alignBearLoss/alignBearTotal*100, 1), "%");
          if(counterBearTotal > 0)
             Print("❌ COUNTER HTF  | 🔴 VENTAS (", counterBearTotal, ") | F50: ", DoubleToString((double)counterBearF50/counterBearTotal*100, 1), "% | F100: ", DoubleToString((double)counterBearF100/counterBearTotal*100, 1), "% | Loss: ", DoubleToString((double)counterBearLoss/counterBearTotal*100, 1), "%");
          if(neutralBearTotal > 0)
             Print("⚪ NEUTRAL HTF  | 🔴 VENTAS (", neutralBearTotal, ") | F50: ", DoubleToString((double)neutralBearF50/neutralBearTotal*100, 1), "% | F100: ", DoubleToString((double)neutralBearF100/neutralBearTotal*100, 1), "% | Loss: ", DoubleToString((double)neutralBearLoss/neutralBearTotal*100, 1), "%");
             
          Print("---------------------------------------------------------");
             
          // Imprimir Compras
          if(baseBullTotal > 0)
             Print("🌐 BASELINE LTF | 🟢 COMPRAS (", baseBullTotal, ") | F50: ", DoubleToString((double)baseBullF50/baseBullTotal*100, 1), "% | F100: ", DoubleToString((double)baseBullF100/baseBullTotal*100, 1), "% | Loss: ", DoubleToString((double)baseBullLoss/baseBullTotal*100, 1), "%");
          if(alignBullTotal > 0)
             Print("✅ ALINEADO HTF | 🟢 COMPRAS (", alignBullTotal, ") | F50: ", DoubleToString((double)alignBullF50/alignBullTotal*100, 1), "% | F100: ", DoubleToString((double)alignBullF100/alignBullTotal*100, 1), "% | Loss: ", DoubleToString((double)alignBullLoss/alignBullTotal*100, 1), "%");
          if(counterBullTotal > 0)
             Print("❌ COUNTER HTF  | 🟢 COMPRAS (", counterBullTotal, ") | F50: ", DoubleToString((double)counterBullF50/counterBullTotal*100, 1), "% | F100: ", DoubleToString((double)counterBullF100/counterBullTotal*100, 1), "% | Loss: ", DoubleToString((double)counterBullLoss/counterBullTotal*100, 1), "%");
          if(neutralBullTotal > 0)
             Print("⚪ NEUTRAL HTF  | 🟢 COMPRAS (", neutralBullTotal, ") | F50: ", DoubleToString((double)neutralBullF50/neutralBullTotal*100, 1), "% | F100: ", DoubleToString((double)neutralBullF100/neutralBullTotal*100, 1), "% | Loss: ", DoubleToString((double)neutralBullLoss/neutralBullTotal*100, 1), "%");
             
          Print("=========================================================");
       }
     Print("================= FIN DEL ANÁLISIS DE BIAS =================");
  }

//+------------------------------------------------------------------+
//| Devuelve: 1 (Bullish HTF), -1 (Bearish HTF), 0 (Neutral)         |
//| Evalúa SWEEPS (hasta final de rango) y RUNS (hasta rotura SL)    |
//+------------------------------------------------------------------+
int GetActiveHTFBias(string sym, ENUM_TIMEFRAMES tf, datetime currentTime)
  {
     int currentShift = iBarShift(sym, tf, currentTime);
     
     // Miramos hasta 3 velas atrás en el HTF para buscar el patrón dominante más reciente
     for(int k = 1; k <= 3; k++)
       {
          int patternIdx = currentShift + k;
          double prevHigh = iHigh(sym, tf, patternIdx+1);
          double prevLow  = iLow(sym, tf, patternIdx+1);
          
          double curHigh  = iHigh(sym, tf, patternIdx);
          double curLow   = iLow(sym, tf, patternIdx);
          double curClose = iClose(sym, tf, patternIdx);
          
          // --------------------------------------------------------
          // 1. Evaluar si es un Bearish Sweep en HTF
          // --------------------------------------------------------
          if(curHigh > prevHigh && curClose < prevHigh)
            {
               double sl = curHigh;          
               double target = prevLow;      
               bool isAlive = true;
               
               for(int j = patternIdx - 1; j >= currentShift; j--)
                 {
                    if(iHigh(sym, tf, j) >= sl || iLow(sym, tf, j) <= target) { isAlive = false; break; }
                 }
               if(isAlive) return -1; 
            }
            
          // --------------------------------------------------------
          // 2. Evaluar si es un Bullish Sweep en HTF
          // --------------------------------------------------------
          if(curLow < prevLow && curClose > prevLow)
            {
               double sl = curLow;           
               double target = prevHigh;     
               bool isAlive = true;
               
               for(int j = patternIdx - 1; j >= currentShift; j--)
                 {
                    if(iLow(sym, tf, j) <= sl || iHigh(sym, tf, j) >= target) { isAlive = false; break; }
                 }
               if(isAlive) return 1;  
            }
            
          // --------------------------------------------------------
          // 3. Evaluar si es un Bearish RUN en HTF
          // --------------------------------------------------------
          if(curClose < prevLow)
            {
               double sl = curHigh; 
               bool isAlive = true;
               
               for(int j = patternIdx - 1; j >= currentShift; j--)
                 {
                    if(iHigh(sym, tf, j) >= sl) { isAlive = false; break; }
                 }
               if(isAlive) return -1; 
            }
            
          // --------------------------------------------------------
          // 4. Evaluar si es un Bullish RUN en HTF
          // --------------------------------------------------------
          if(curClose > prevHigh)
            {
               double sl = curLow; 
               bool isAlive = true;
               
               for(int j = patternIdx - 1; j >= currentShift; j--)
                 {
                    if(iLow(sym, tf, j) <= sl) { isAlive = false; break; }
                 }
               if(isAlive) return 1;  
            }
       }
       
     return 0; // Bias NEUTRO
  }