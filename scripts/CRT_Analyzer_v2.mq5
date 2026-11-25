//+------------------------------------------------------------------+
//|                               CRT_MultiTF_BatchAnalyzer.mq5      |
//|  Analizador de Rendimiento Mecánico CRT (Batch Multi-Timeframe)  |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "2.00"
#property script_show_inputs

input int    InpHistoryBars = 10000;  // Velas históricas a analizar por TF
input double InpMinPips     = 5.0;    // Tamaño mínimo de la Vela Base (Pips)

double g_pip;

// Estructura para almacenar estadísticas de cada fase
struct SweepStats
  {
   int total;
   int tp;
   int hit_50;
   int sl;

   void Reset()
     {
      total = 0; tp = 0; hit_50 = 0; sl = 0;
     }

   void Add(int result, bool reached_50)
     {
      total++;
      if(result == 1) { tp++; hit_50++; } // Si es TP, implícitamente llegó al 50%
      else if(result == -1)
        {
         sl++;
         if(reached_50) hit_50++;
        }
     }

   void PrintStats(string label)
     {
      double tp_pct = total > 0 ? (double)tp / total * 100.0 : 0.0;
      double h50_pct = total > 0 ? (double)hit_50 / total * 100.0 : 0.0;
      PrintFormat("%s | Total: %d | TP (100%%): %d (%.1f%%) | Llegan 50%%: %d (%.1f%%) | SL: %d",
                  label, total, tp, tp_pct, hit_50, h50_pct, sl);
     }
  };

//+------------------------------------------------------------------+
//| Función principal de análisis por temporalidad                   |
//+------------------------------------------------------------------+
void AnalyzeTimeframe(ENUM_TIMEFRAMES tf, string tfName)
  {
   SweepStats stats_bull[4];
   SweepStats stats_bear[4];
   
   for(int i=0; i<4; i++)
     {
      stats_bull[i].Reset();
      stats_bear[i].Reset();
     }

   int limit = MathMin(iBars(_Symbol, tf) - 2, InpHistoryBars);
   if(limit <= 0)
     {
      PrintFormat(">>> Advertencia: No hay suficiente historial para %s", tfName);
      return;
     }

   int i = limit;

   // Recorrido cronológico (de pasado a presente)
   while(i >= 1)
     {
      double baseH = iHigh(_Symbol, tf, i);
      double baseL = iLow(_Symbol, tf, i);
      
      if(baseH - baseL < InpMinPips * g_pip) 
        { i--; continue; }

      int state = 0; // 0 = Buscando, 1 = Bull Activo, -1 = Bear Activo
      int sweeps = 0;
      double currentSL = 0, targetFull = 0, target50 = 0;
      bool hit50 = false;
      int break_k = -1; // Para saltar el bucle a la vela donde termina el rango

      for(int k = i - 1; k >= 0; k--)
        {
         double cH = iHigh(_Symbol, tf, k);
         double cL = iLow(_Symbol, tf, k);
         double cC = iClose(_Symbol, tf, k);
         double cO = iOpen(_Symbol, tf, k);

         // === ESTADO 0: ESPERANDO ACTIVACIÓN ===
         if(state == 0)
           {
            if(cC > baseH || cC < baseL) // Invalida la Vela Base antes de hacer un sweep
              { break_k = k; break; }

            // BARRIDA ALCISTA
            if(cL < baseL && cC >= baseL && cC <= baseH)
              {
               state = 1; sweeps = 1; hit50 = false;
               currentSL = cL; 
               targetFull = baseH; 
               target50 = baseL + (baseH - baseL) * 0.5;

               if(cH >= target50) hit50 = true;
               // Tipo 2: Logra el TP en la misma vela de activación
               if(cH >= targetFull)
                 {
                  stats_bull[sweeps].Add(1, true);
                  break_k = k; break;
                 }
              }
            // BARRIDA BAJISTA
            else if(cH > baseH && cC <= baseH && cC >= baseL)
              {
               state = -1; sweeps = 1; hit50 = false;
               currentSL = cH; 
               targetFull = baseL; 
               target50 = baseH - (baseH - baseL) * 0.5;

               if(cL <= target50) hit50 = true;
               // Tipo 2: Logra el TP en la misma vela de activación
               if(cL <= targetFull)
                 {
                  stats_bear[sweeps].Add(1, true);
                  break_k = k; break;
                 }
              }
           }
           
         // === ESTADO 1: BULLISH ACTIVO ===
         else if(state == 1)
           {
            if(cH >= target50) hit50 = true;

            bool isTP = (cH >= targetFull);
            bool isSL = (cL <= currentSL);

            // Colisión Intrabarra: Estimación conservadora por distancia al Open
            if(isTP && isSL)
              {
               if(MathAbs(cO - currentSL) <= MathAbs(targetFull - cO)) isTP = false; // SL primero
               else isSL = false; // TP primero
              }

            if(isTP)
              {
               stats_bull[MathMin(sweeps, 3)].Add(1, true);
               break_k = k; break;
              }
            if(isSL)
              {
               stats_bull[MathMin(sweeps, 3)].Add(-1, hit50); // Registramos pérdida del sweep anterior
               
               // ¿Doble/Triple Liquidez? Si cierra dentro de la base, es un nuevo sweep
               if(cC >= baseL && cC <= baseH)
                 {
                  sweeps++;
                  currentSL = cL; 
                  hit50 = false;
                  if(cH >= target50) hit50 = true; // Por si subió al 50% después de barrer
                 }
               else { break_k = k; break; } // Invalida el rango, cierre por debajo
              }
           }
           
         // === ESTADO -1: BEARISH ACTIVO ===
         else if(state == -1)
           {
            if(cL <= target50) hit50 = true;

            bool isTP = (cL <= targetFull);
            bool isSL = (cH >= currentSL);

            // Colisión Intrabarra
            if(isTP && isSL)
              {
               if(MathAbs(cO - currentSL) <= MathAbs(cO - targetFull)) isTP = false;
               else isSL = false;
              }

            if(isTP)
              {
               stats_bear[MathMin(sweeps, 3)].Add(1, true);
               break_k = k; break;
              }
            if(isSL)
              {
               stats_bear[MathMin(sweeps, 3)].Add(-1, hit50); 
               
               if(cC <= baseH && cC >= baseL)
                 {
                  sweeps++;
                  currentSL = cH; 
                  hit50 = false;
                  if(cL <= target50) hit50 = true;
                 }
               else { break_k = k; break; } 
              }
           }
        }

      // Avanzamos el índice general a donde terminó la vida del rango actual
      if(break_k != -1) i = break_k;
      else i--;
     }

   // --- IMPRESIÓN DE RESULTADOS ---
   Print("------------------------------------------------------------------");
   PrintFormat(" [ %s ] Muestra analizada: %d velas", tfName, limit);
   Print("------------------------------------------------------------------");
   Print("> BARRIDAS ALCISTAS");
   stats_bull[1].PrintStats("Sweep 1 (Simple) ");
   stats_bull[2].PrintStats("Sweep 2 (Doble)  ");
   stats_bull[3].PrintStats("Sweep 3+ (Triple)");
   
   Print("> BARRIDAS BAJISTAS");
   stats_bear[1].PrintStats("Sweep 1 (Simple) ");
   stats_bear[2].PrintStats("Sweep 2 (Doble)  ");
   stats_bear[3].PrintStats("Sweep 3+ (Triple)");
   Print(" "); // Espaciador visual entre temporalidades
  }

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
  {
   g_pip = (_Digits == 5 || _Digits == 3) ? _Point * 10 : _Point;
   
   Print("==================================================================");
   PrintFormat(" INICIANDO BATCH TEST CRT (%s)", _Symbol);
   Print("==================================================================");

   // Arrays con las temporalidades y sus nombres a analizar
   ENUM_TIMEFRAMES timeframes[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H4};
   string tfNames[] = {"Mensual (MN1)", "Semanal (W1)", "Diario (D1)", "12 Horas (H12)", "8 Horas (H8)", "4 Horas (H4)"};

   int num_tfs = ArraySize(timeframes);
   
   for(int i = 0; i < num_tfs; i++)
     {
      AnalyzeTimeframe(timeframes[i], tfNames[i]);
     }
     
   Print("==================================================================");
   Print(" EXTRACCIÓN DE DATOS FINALIZADA");
   Print("==================================================================");
  }
//+------------------------------------------------------------------+