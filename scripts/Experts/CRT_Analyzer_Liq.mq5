//+------------------------------------------------------------------+
//|                                   CRT_Universal_Liquidity_V8.mq5 |
//|         Test de Pureza: Sweeps de H4/H8/H12 en Niveles Clave     |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "8.01"
#property script_show_inputs

input int InpHistoryBars = 1000; // Velas a analizar por Timeframe

// Horarios de Sesión (Hora del Bróker)
input int AsiaStartHour = 0;  
input int AsiaEndHour   = 8;  
input int LonStartHour  = 10;  
input int LonEndHour    = 14; 

// CORRECCIÓN: Cambiamos 'struct' por 'class' para poder usar punteros en MQL5
class SweepStats {
public:
   int total;
   int win50;
   int win100;
   int loss;
   
   // Constructor para inicializar a cero
   SweepStats() { total = 0; win50 = 0; win100 = 0; loss = 0; }
};

//+------------------------------------------------------------------+
void OnStart()
  {
     ENUM_TIMEFRAMES timeframes[] = {PERIOD_H4, PERIOD_H8, PERIOD_H12};
     int numTFs = ArraySize(timeframes);

     Print("=====================================================================");
     Print(" INICIANDO MATRIZ DE LIQUIDEZ UNIVERSAL PARA: ", _Symbol);
     Print(" Evaluando PWL/PWH, PDL/PDH, Asia y Londres");
     Print("=====================================================================");

     for(int t = 0; t < numTFs; t++)
       {
          ENUM_TIMEFRAMES curTF = timeframes[t];
          string tfName = EnumToString(curTF);
          
          // Instanciamos las clases
          SweepStats bearW, bearD, bearA, bearL;
          SweepStats bullW, bullD, bullA, bullL;

          int bars = iBars(_Symbol, curTF);
          int limit = MathMin(bars - 2, InpHistoryBars); 
          
          if(limit <= 0) continue;

          for(int i = limit; i >= 1; i--)
            {
               datetime candleTime = iTime(_Symbol, curTF, i);
               datetime dayStart = candleTime - (candleTime % 86400); // 00:00 del día actual
               
               // 1. Niveles Semanales (Previous Week)
               int wIdx = iBarShift(_Symbol, PERIOD_W1, candleTime) + 1;
               double pwh = iHigh(_Symbol, PERIOD_W1, wIdx);
               double pwl = iLow(_Symbol, PERIOD_W1, wIdx);

               // 2. Niveles Diarios (Previous Day)
               int dIdx = iBarShift(_Symbol, PERIOD_D1, candleTime) + 1;
               double pdh = iHigh(_Symbol, PERIOD_D1, dIdx);
               double pdl = iLow(_Symbol, PERIOD_D1, dIdx);

               // 3. Niveles de Asia y Londres (Dinámicos)
               double asiaH = 0, asiaL = 999999, lonH = 0, lonL = 999999;
               
               // Buscar el Asia más reciente (Hoy o Ayer)
               datetime aEnd = dayStart + AsiaEndHour*3600;
               datetime aStart = dayStart + AsiaStartHour*3600;
               if(candleTime < aEnd) { aEnd -= 86400; aStart -= 86400; } // Usar ayer
               
               int aStartIdx = iBarShift(_Symbol, PERIOD_M15, aStart);
               int aEndIdx = iBarShift(_Symbol, PERIOD_M15, aEnd);
               if(aStartIdx != -1 && aEndIdx != -1) {
                  int hIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, aStartIdx-aEndIdx+1, aEndIdx);
                  int lIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW, aStartIdx-aEndIdx+1, aEndIdx);
                  if(hIdx != -1) asiaH = iHigh(_Symbol, PERIOD_M15, hIdx);
                  if(lIdx != -1) asiaL = iLow(_Symbol, PERIOD_M15, lIdx);
               }

               // Buscar el Londres más reciente (Hoy o Ayer)
               datetime lEnd = dayStart + LonEndHour*3600;
               datetime lStart = dayStart + LonStartHour*3600;
               if(candleTime < lEnd) { lEnd -= 86400; lStart -= 86400; } // Usar ayer
               
               int lStartIdx = iBarShift(_Symbol, PERIOD_M15, lStart);
               int lEndIdx = iBarShift(_Symbol, PERIOD_M15, lEnd);
               if(lStartIdx != -1 && lEndIdx != -1) {
                  int hIdx = iHighest(_Symbol, PERIOD_M15, MODE_HIGH, lStartIdx-lEndIdx+1, lEndIdx);
                  int lowIdx = iLowest(_Symbol, PERIOD_M15, MODE_LOW, lStartIdx-lEndIdx+1, lEndIdx);
                  if(hIdx != -1) lonH = iHigh(_Symbol, PERIOD_M15, hIdx);
                  if(lowIdx != -1) lonL = iLow(_Symbol, PERIOD_M15, lowIdx);
               }

               // Datos de la Vela Actual
               double curHigh = iHigh(_Symbol, curTF, i);
               double curLow = iLow(_Symbol, curTF, i);
               double curClose = iClose(_Symbol, curTF, i);

               // =========================================================
               // EVALUAR BEARISH SWEEPS (Prioridad: Semanal > Diario > Sesión)
               // =========================================================
               double stopLoss = curHigh;
               double target100 = 0;
               SweepStats *activeBearStats = NULL;

               if(curHigh > pwh && curClose < pwh) { target100 = pwl; activeBearStats = GetPointer(bearW); }
               else if(curHigh > pdh && curClose < pdh) { target100 = pdl; activeBearStats = GetPointer(bearD); }
               else if(curHigh > lonH && curClose < lonH && lonH > 0) { target100 = lonL; activeBearStats = GetPointer(bearL); }
               else if(curHigh > asiaH && curClose < asiaH && asiaH > 0) { target100 = asiaL; activeBearStats = GetPointer(bearA); }

               if(activeBearStats != NULL && target100 > 0)
                 {
                    activeBearStats.total++;
                    double sweptLevel = (activeBearStats == GetPointer(bearW)) ? pwh : (activeBearStats == GetPointer(bearD)) ? pdh : (activeBearStats == GetPointer(bearL)) ? lonH : asiaH;
                    double target50 = sweptLevel - ((sweptLevel - target100) * 0.5);
                    
                    bool hit50 = false, hit100 = false, hitLoss = false;
                    for(int j = i - 1; j >= 0; j--) {
                       double fHigh = iHigh(_Symbol, curTF, j);
                       double fLow  = iLow(_Symbol, curTF, j);
                       if(fHigh > stopLoss && !hit50 && !hit100) { hitLoss = true; break; }
                       if(fLow <= target50 && !hit50) hit50 = true;
                       if(fLow <= target100 && !hit100) hit100 = true;
                       if(hit100 || fHigh > stopLoss) break;   
                    }
                    if(hit50) activeBearStats.win50++;
                    if(hit100) activeBearStats.win100++;
                    if(hitLoss && !hit50) activeBearStats.loss++;
                 }

               // =========================================================
               // EVALUAR BULLISH SWEEPS
               // =========================================================
               stopLoss = curLow;
               target100 = 0;
               SweepStats *activeBullStats = NULL;

               if(curLow < pwl && curClose > pwl) { target100 = pwh; activeBullStats = GetPointer(bullW); }
               else if(curLow < pdl && curClose > pdl) { target100 = pdh; activeBullStats = GetPointer(bullD); }
               else if(curLow < lonL && curClose > lonL && lonL != 999999) { target100 = lonH; activeBullStats = GetPointer(bullL); }
               else if(curLow < asiaL && curClose > asiaL && asiaL != 999999) { target100 = asiaH; activeBullStats = GetPointer(bullA); }

               if(activeBullStats != NULL && target100 > 0)
                 {
                    activeBullStats.total++;
                    double sweptLevel = (activeBullStats == GetPointer(bullW)) ? pwl : (activeBullStats == GetPointer(bullD)) ? pdl : (activeBullStats == GetPointer(bullL)) ? lonL : asiaL;
                    double target50 = sweptLevel + ((target100 - sweptLevel) * 0.5);
                    
                    bool hit50 = false, hit100 = false, hitLoss = false;
                    for(int j = i - 1; j >= 0; j--) {
                       double fHigh = iHigh(_Symbol, curTF, j);
                       double fLow  = iLow(_Symbol, curTF, j);
                       if(fLow < stopLoss && !hit50 && !hit100) { hitLoss = true; break; }
                       if(fHigh >= target50 && !hit50) hit50 = true;
                       if(fHigh >= target100 && !hit100) hit100 = true;
                       if(hit100 || fLow < stopLoss) break;   
                    }
                    if(hit50) activeBullStats.win50++;
                    if(hit100) activeBullStats.win100++;
                    if(hitLoss && !hit50) activeBullStats.loss++;
                 }
            }

          // --- IMPRIMIR RESULTADOS ---
          Print("----- TIMEFRAME: ", tfName, " -----");
          
          if(bearW.total > 0) Print("🔴 WEEKLY (PWH) Sweeps: ", bearW.total, " | Win 50%: ", DoubleToString((double)bearW.win50/bearW.total*100,1), "% | Win 100%: ", DoubleToString((double)bearW.win100/bearW.total*100,1), "%");
          if(bearD.total > 0) Print("🔴 DAILY (PDH)  Sweeps: ", bearD.total, " | Win 50%: ", DoubleToString((double)bearD.win50/bearD.total*100,1), "% | Win 100%: ", DoubleToString((double)bearD.win100/bearD.total*100,1), "%");
          if(bearL.total > 0) Print("🔴 LONDON High  Sweeps: ", bearL.total, " | Win 50%: ", DoubleToString((double)bearL.win50/bearL.total*100,1), "% | Win 100%: ", DoubleToString((double)bearL.win100/bearL.total*100,1), "%");
          if(bearA.total > 0) Print("🔴 ASIA High    Sweeps: ", bearA.total, " | Win 50%: ", DoubleToString((double)bearA.win50/bearA.total*100,1), "% | Win 100%: ", DoubleToString((double)bearA.win100/bearA.total*100,1), "%");

          if(bullW.total > 0) Print("🟢 WEEKLY (PWL) Sweeps: ", bullW.total, " | Win 50%: ", DoubleToString((double)bullW.win50/bullW.total*100,1), "% | Win 100%: ", DoubleToString((double)bullW.win100/bullW.total*100,1), "%");
          if(bullD.total > 0) Print("🟢 DAILY (PDL)  Sweeps: ", bullD.total, " | Win 50%: ", DoubleToString((double)bullD.win50/bullD.total*100,1), "% | Win 100%: ", DoubleToString((double)bullD.win100/bullD.total*100,1), "%");
          if(bullL.total > 0) Print("🟢 LONDON Low   Sweeps: ", bullL.total, " | Win 50%: ", DoubleToString((double)bullL.win50/bullL.total*100,1), "% | Win 100%: ", DoubleToString((double)bullL.win100/bullL.total*100,1), "%");
          if(bullA.total > 0) Print("🟢 ASIA Low     Sweeps: ", bullA.total, " | Win 50%: ", DoubleToString((double)bullA.win50/bullA.total*100,1), "% | Win 100%: ", DoubleToString((double)bullA.win100/bullA.total*100,1), "%");
          
          Print("---------------------------------------");
       }
     Print("================= FIN DE LA MATRIZ DE LIQUIDEZ =================");
  }