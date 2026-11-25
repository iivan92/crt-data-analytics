//+------------------------------------------------------------------+
//|                               CRT_Ultimate_Stats_Matrix.mq5      |
//|  WR Global vs WR Limpio vs WR Reiniciado (con Sweeps Múltiples)  |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "5.00"
#property script_show_inputs

input int    InpHistoryBars        = 10000; // Velas históricas a analizar
input double InpMinPips            = 5.0;   // Tamaño mínimo de la Vela Base
input bool   InpSeparateDirections = true;  // TRUE = Separa Compras/Ventas | FALSE = Todo junto

double g_pip;

// Estructura para almacenar estadísticas cruzadas
struct SweepMatrix
  {
   int total_activados;
   int tp_total;
   
   int total_limpios;
   int tp_limpios;
   
   int total_reiniciados;
   int tp_reiniciados;

   void Reset()
     {
      total_activados = 0; tp_total = 0;
      total_limpios = 0; tp_limpios = 0;
      total_reiniciados = 0; tp_reiniciados = 0;
     }

   void Add(int result, bool has_restarted)
     {
      total_activados++;
      if(result == 1) tp_total++;
      
      if(has_restarted)
        {
         total_reiniciados++;
         if(result == 1) tp_reiniciados++;
        }
      else
        {
         total_limpios++;
         if(result == 1) tp_limpios++;
        }
     }

   void PrintStats(string label)
     {
      if(total_activados == 0) return;
      
      double wr_global = (double)tp_total / total_activados * 100.0;
      double wr_limpio = total_limpios > 0 ? (double)tp_limpios / total_limpios * 100.0 : 0.0;
      double wr_reinicio = total_reiniciados > 0 ? (double)tp_reiniciados / total_reiniciados * 100.0 : 0.0;
      double pct_reinicio = (double)total_reiniciados / total_activados * 100.0;
      
      PrintFormat("%s | Total: %d | WR Global: %.1f%%", label, total_activados, wr_global);
      PrintFormat("   -> Limpios: %d | WR Limpio: %.1f%%", total_limpios, wr_limpio);
      PrintFormat("   -> Con Reinicio: %d (%.1f%%) | WR si Reinicia: %.1f%%", total_reiniciados, pct_reinicio, wr_reinicio);
     }
  };

void AnalyzeTimeframe(ENUM_TIMEFRAMES tf, string tfName)
  {
   SweepMatrix stats_bull[4], stats_bear[4], stats_combined[4];
   for(int i=0; i<4; i++) { stats_bull[i].Reset(); stats_bear[i].Reset(); stats_combined[i].Reset(); }

   int limit = MathMin(iBars(_Symbol, tf) - 2, InpHistoryBars);
   if(limit <= 0) return;

   int i = limit;

   while(i >= 1)
     {
      double baseH = iHigh(_Symbol, tf, i);
      double baseL = iLow(_Symbol, tf, i);
      
      if(baseH - baseL < InpMinPips * g_pip) { i--; continue; }

      int state = 0; 
      int sweeps = 0;
      double currentSL = 0, targetFull = 0, triggerExtreme = 0;
      bool has_restarted = false;
      int break_k = -1; 

      for(int k = i - 1; k >= 0; k--)
        {
         double cH = iHigh(_Symbol, tf, k);
         double cL = iLow(_Symbol, tf, k);
         double cC = iClose(_Symbol, tf, k);
         double cO = iOpen(_Symbol, tf, k);

         // === ESTADO 0: ESPERANDO ACTIVACIÓN ===
         if(state == 0)
           {
            if(cC > baseH || cC < baseL) { break_k = k; break; }

            // BARRIDA ALCISTA
            if(cL < baseL && cC >= baseL && cC <= baseH)
              {
               state = 1; sweeps = 1; has_restarted = false;
               currentSL = cL; targetFull = baseH; triggerExtreme = cH; 
               
               if(cH >= targetFull) 
                 { 
                  stats_bull[sweeps].Add(1, false); stats_combined[sweeps].Add(1, false); 
                  break_k = k; break; 
                 }
              }
            // BARRIDA BAJISTA
            else if(cH > baseH && cC <= baseH && cC >= baseL)
              {
               state = -1; sweeps = 1; has_restarted = false;
               currentSL = cH; targetFull = baseL; triggerExtreme = cL; 
               
               if(cL <= targetFull) 
                 { 
                  stats_bear[sweeps].Add(1, false); stats_combined[sweeps].Add(1, false); 
                  break_k = k; break; 
                 }
              }
           }
           
         // === ESTADO 1: BULLISH ACTIVO ===
         else if(state == 1)
           {
            bool isTP = (cH >= targetFull);
            bool isSL = (cL <= currentSL);

            if(isTP && isSL) { if(MathAbs(cO - currentSL) <= MathAbs(targetFull - cO)) isTP = false; else isSL = false; }

            if(isTP)
              {
               stats_bull[MathMin(sweeps, 3)].Add(1, has_restarted);
               stats_combined[MathMin(sweeps, 3)].Add(1, has_restarted);
               break_k = k; break;
              }
            else if(isSL)
              {
               stats_bull[MathMin(sweeps, 3)].Add(-1, has_restarted);
               stats_combined[MathMin(sweeps, 3)].Add(-1, has_restarted);
               
               if(cC >= baseL && cC <= baseH) 
                 { sweeps++; currentSL = cL; triggerExtreme = cH; has_restarted = false; } // Nuevo Sweep
               else { break_k = k; break; } // Descartado
              }
            else if(!has_restarted)
              {
               if(cH > triggerExtreme && cC < triggerExtreme) has_restarted = true; // Trampa bajista
              }
           }
           
         // === ESTADO -1: BEARISH ACTIVO ===
         else if(state == -1)
           {
            bool isTP = (cL <= targetFull);
            bool isSL = (cH >= currentSL);

            if(isTP && isSL) { if(MathAbs(cO - currentSL) <= MathAbs(cO - targetFull)) isTP = false; else isSL = false; }

            if(isTP)
              {
               stats_bear[MathMin(sweeps, 3)].Add(1, has_restarted);
               stats_combined[MathMin(sweeps, 3)].Add(1, has_restarted);
               break_k = k; break;
              }
            else if(isSL)
              {
               stats_bear[MathMin(sweeps, 3)].Add(-1, has_restarted);
               stats_combined[MathMin(sweeps, 3)].Add(-1, has_restarted);
               
               if(cC <= baseH && cC >= baseL) 
                 { sweeps++; currentSL = cH; triggerExtreme = cL; has_restarted = false; } // Nuevo Sweep
               else { break_k = k; break; } // Descartado
              }
            else if(!has_restarted)
              {
               if(cL < triggerExtreme && cC > triggerExtreme) has_restarted = true; // Trampa alcista
              }
           }
        }

      if(break_k != -1) i = break_k; else i--;
     }

   // --- IMPRESIÓN ---
   Print("------------------------------------------------------------------");
   PrintFormat(" [ %s ] Muestra analizada: %d velas", tfName, limit);
   Print("------------------------------------------------------------------");
   
   if(InpSeparateDirections)
     {
      Print("> ALCISTAS");
      stats_bull[1].PrintStats("Sweep 1"); stats_bull[2].PrintStats("Sweep 2"); stats_bull[3].PrintStats("Sweep 3+");
      Print("> BAJISTAS");
      stats_bear[1].PrintStats("Sweep 1"); stats_bear[2].PrintStats("Sweep 2"); stats_bear[3].PrintStats("Sweep 3+");
     }
   else
     {
      Print("> RENDIMIENTO COMBINADO (Alcista + Bajista)");
      stats_combined[1].PrintStats("Sweep 1");
      stats_combined[2].PrintStats("Sweep 2");
      stats_combined[3].PrintStats("Sweep 3+");
     }
   Print(" ");
  }

void OnStart()
  {
   g_pip = (_Digits == 5 || _Digits == 3) ? _Point * 10 : _Point;
   
   Print("==================================================================");
   PrintFormat(" MATRIZ CRT: LIMPIOS VS REINICIADOS (%s)", _Symbol);
   PrintFormat(" Modo: %s", InpSeparateDirections ? "Direcciones Separadas" : "Combinado");
   Print("==================================================================");

   ENUM_TIMEFRAMES timeframes[] = {PERIOD_MN1, PERIOD_W1, PERIOD_D1, PERIOD_H12, PERIOD_H8, PERIOD_H4};
   string tfNames[] = {"Mensual (MN1)", "Semanal (W1)", "Diario (D1)", "12 Horas (H12)", "8 Horas (H8)", "4 Horas (H4)"};

   for(int i = 0; i < ArraySize(timeframes); i++) AnalyzeTimeframe(timeframes[i], tfNames[i]);
  }
//+------------------------------------------------------------------+