//+------------------------------------------------------------------+
//|                                  CRT_Continuous_RR_V7_CSV.mq5    |
//|  Simulador Fractal Continuo. Cosecha múltiples trades en LTF     |
//|  mientras el sesgo del HTF siga vivo. HTF: H12, H8, H4 | LTF: H1, M15 |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "7.00"
#property script_show_inputs

input int    InpHistoryBars = 15000; // Velas históricas en LTF
input double InpMinPips     = 3.0;   // Filtro: Tamaño mínimo del riesgo/rango en pips

int csvHandle = INVALID_HANDLE;
double g_pip;

//+------------------------------------------------------------------+
//  STRUCT: Acumulador de estadísticas Risk / Reward
//+------------------------------------------------------------------+
struct RRStats
  {
   int    total_ltf_trades;
   int    unique_htf_waves; // Cuántos movimientos macro únicos generaron trades
   
   int    hit_1R;
   int    hit_2R;
   int    hit_3R;
   int    hit_4R;
   int    hit_HTF_Target;
   int    sl_direct;

   void   Reset() { total_ltf_trades=0; unique_htf_waves=0; hit_1R=0; hit_2R=0; hit_3R=0; hit_4R=0; hit_HTF_Target=0; sl_direct=0; }
   
   double AvgTrades() { return unique_htf_waves > 0 ? (double)total_ltf_trades / unique_htf_waves : 0.0; }
   double Pct1R()  { return total_ltf_trades > 0 ? (double)hit_1R / total_ltf_trades * 100.0 : 0.0; }
   double Pct2R()  { return total_ltf_trades > 0 ? (double)hit_2R / total_ltf_trades * 100.0 : 0.0; }
   double Pct3R()  { return total_ltf_trades > 0 ? (double)hit_3R / total_ltf_trades * 100.0 : 0.0; }
   double Pct4R()  { return total_ltf_trades > 0 ? (double)hit_4R / total_ltf_trades * 100.0 : 0.0; }
   double PctHTF() { return total_ltf_trades > 0 ? (double)hit_HTF_Target / total_ltf_trades * 100.0 : 0.0; }
   double PctSL()  { return total_ltf_trades > 0 ? (double)sl_direct / total_ltf_trades * 100.0 : 0.0; }
  };

#define PAT_BULL_SWEEP  0
#define PAT_BEAR_SWEEP  1
#define PAT_BULL_RUN    2
#define PAT_BEAR_RUN    3
#define PAT_NONE       -1

bool IsBull(int p) { return p == PAT_BULL_SWEEP || p == PAT_BULL_RUN; }
bool IsBear(int p) { return p == PAT_BEAR_SWEEP || p == PAT_BEAR_RUN; }

string GetPatName(int p)
  {
   if(p == PAT_BULL_SWEEP) return "Bull Sweep";
   if(p == PAT_BEAR_SWEEP) return "Bear Sweep";
   if(p == PAT_BULL_RUN)   return "Bull Run";
   if(p == PAT_BEAR_RUN)   return "Bear Run";
   return "None";
  }

//+------------------------------------------------------------------+
//  Rastreo Estructural (Mother Bar)
//+------------------------------------------------------------------+
void GetMotherBarLevels(ENUM_TIMEFRAMES tf, int signalBar, double &mbH, double &mbL, double &bearSweepLvl, double &bullSweepLvl)
  {
   int limit = iBars(_Symbol, tf) - 1;
   int mbIdx = signalBar + 1;
   if(mbIdx > limit) { mbH = 0; mbL = 0; bearSweepLvl = 0; bullSweepLvl = 0; return; }

   mbH = iHigh(_Symbol, tf, mbIdx);
   mbL = iLow(_Symbol, tf, mbIdx);

   while(mbIdx < limit)
     {
      double prevH = iHigh(_Symbol, tf, mbIdx+1);
      double prevL = iLow(_Symbol, tf, mbIdx+1);
      if(mbH <= prevH && mbL >= prevL) { mbIdx++; mbH = prevH; mbL = prevL; }
      else break;
     }

   bearSweepLvl = iHigh(_Symbol, tf, signalBar + 1);
   bullSweepLvl = iLow(_Symbol, tf, signalBar + 1);

   if(mbIdx != signalBar + 1)
     {
      double mbOpen = iOpen(_Symbol, tf, mbIdx);
      double mbClose = iClose(_Symbol, tf, mbIdx);
      if(mbClose < mbOpen)      bullSweepLvl = mbL; 
      else if(mbClose > mbOpen) bearSweepLvl = mbH; 
      else { bearSweepLvl = mbH; bullSweepLvl = mbL; }
     }
  }

int DetectCRT(ENUM_TIMEFRAMES tf, int bar)
  {
   int totalBars = iBars(_Symbol, tf);
   if(bar + 1 >= totalBars || bar < 0) return PAT_NONE;

   double mbH, mbL, bearSweepLvl, bullSweepLvl;
   GetMotherBarLevels(tf, bar, mbH, mbL, bearSweepLvl, bullSweepLvl);

   if((mbH - mbL) < InpMinPips * g_pip) return PAT_NONE;

   double cH = iHigh (_Symbol, tf, bar);
   double cL = iLow  (_Symbol, tf, bar);
   double cC = iClose(_Symbol, tf, bar);

   if(cH > bearSweepLvl && cC < bearSweepLvl) return PAT_BEAR_SWEEP;
   if(cL < bullSweepLvl && cC > bullSweepLvl) return PAT_BULL_SWEEP;
   if(cH > bearSweepLvl && cC > bearSweepLvl) return PAT_BULL_RUN;
   if(cL < bullSweepLvl && cC < bullSweepLvl) return PAT_BEAR_RUN;

   return PAT_NONE;
  }

//+------------------------------------------------------------------+
//  Estado Activo del HTF (Calcula si la ola macro sigue viva)
//+------------------------------------------------------------------+
int GetActiveHTFState(ENUM_TIMEFRAMES htf, datetime ltf_time, double &out_htf_target, datetime &out_signal_time, int &out_htf_pat)
  {
   int currentShift = iBarShift(_Symbol, htf, ltf_time);
   
   for(int k = 1; k <= 3; k++)
     {
      int patternIdx = currentShift + k;
      int pat = DetectCRT(htf, patternIdx);
      
      if(pat == PAT_NONE) continue;
      
      double mbH, mbL, bSwp, bullSwp;
      GetMotherBarLevels(htf, patternIdx, mbH, mbL, bSwp, bullSwp);
      double pR = mbH - mbL;
      
      double sl, target;
      bool isBull = IsBull(pat);
      
      // Proyección Macro de H12/H8/H4
      if(pat == PAT_BULL_SWEEP)      { sl = iLow(_Symbol, htf, patternIdx); target = mbL + (pR * 0.5); }
      else if(pat == PAT_BEAR_SWEEP) { sl = iHigh(_Symbol, htf, patternIdx); target = mbH - (pR * 0.5); }
      else if(pat == PAT_BULL_RUN)   { sl = iLow(_Symbol, htf, patternIdx); target = mbH + (pR * 0.618); }
      else                           { sl = iHigh(_Symbol, htf, patternIdx); target = mbL - (pR * 0.618); }
      
      bool isAlive = true;
      
      // Comprobar si la ola sobrevivió a las velas cerradas del HTF posteriores
      for(int j = patternIdx - 1; j >= currentShift + 1; j--)
        {
         if(isBull) { if(iLow(_Symbol, htf, j) <= sl || iHigh(_Symbol, htf, j) >= target) { isAlive = false; break; } }
         else       { if(iHigh(_Symbol, htf, j) >= sl || iLow(_Symbol, htf, j) <= target) { isAlive = false; break; } }
        }
        
      if(isAlive)
        {
         out_htf_target = target;
         out_signal_time = iTime(_Symbol, htf, patternIdx);
         out_htf_pat = pat;
         return isBull ? 1 : -1;
        }
     }
   return 0; // Bias Neutro
  }

//+------------------------------------------------------------------+
//  Resolución del Trade LTF con Múltiplos y Target Macro
//+------------------------------------------------------------------+
void ResolveContinuousRR(ENUM_TIMEFRAMES ltf, int ltf_bar, int ltf_pat, double htf_target, RRStats &st)
  {
   bool isBull = IsBull(ltf_pat);
   double entry = iClose(_Symbol, ltf, ltf_bar);
   double sl    = isBull ? iLow(_Symbol, ltf, ltf_bar) : iHigh(_Symbol, ltf, ltf_bar);
   double risk  = MathAbs(entry - sl);
   
   if(risk < InpMinPips * g_pip) return; 
   
   double lvl_1R = isBull ? entry + (risk * 1.0) : entry - (risk * 1.0);
   double lvl_2R = isBull ? entry + (risk * 2.0) : entry - (risk * 2.0);
   double lvl_3R = isBull ? entry + (risk * 3.0) : entry - (risk * 3.0);
   double lvl_4R = isBull ? entry + (risk * 4.0) : entry - (risk * 4.0);

   bool hit_1R = false, hit_2R = false, hit_3R = false, hit_4R = false, hit_HTF = false, hit_SL = false;

   for(int j = ltf_bar - 1; j >= 0; j--)
     {
      double h = iHigh(_Symbol, ltf, j);
      double l = iLow(_Symbol, ltf, j);
      
      if(isBull)
        {
         if(l <= sl) { hit_SL = true; break; } 
         
         if(h >= lvl_1R) hit_1R = true;
         if(h >= lvl_2R) hit_2R = true;
         if(h >= lvl_3R) hit_3R = true;
         if(h >= lvl_4R) hit_4R = true;
         if(h >= htf_target) { hit_HTF = true; break; } 
        }
      else
        {
         if(h >= sl) { hit_SL = true; break; } 
         
         if(l <= lvl_1R) hit_1R = true;
         if(l <= lvl_2R) hit_2R = true;
         if(l <= lvl_3R) hit_3R = true;
         if(l <= lvl_4R) hit_4R = true;
         if(l <= htf_target) { hit_HTF = true; break; } 
        }
     }
     
   st.total_ltf_trades++;
   if(hit_1R)  st.hit_1R++;
   if(hit_2R)  st.hit_2R++;
   if(hit_3R)  st.hit_3R++;
   if(hit_4R)  st.hit_4R++;
   if(hit_HTF) st.hit_HTF_Target++;
   
   if(!hit_1R && hit_SL) st.sl_direct++; 
  }

//+------------------------------------------------------------------+
//  Exportar Línea a CSV
//+------------------------------------------------------------------+
void WriteRRLine(string htfName, string ltfName, string htfPat, string ltfPat, RRStats &s)
  {
   if(s.total_ltf_trades == 0) return;
   
   string line = StringFormat("%s,%s,%s,%s,%d,%d,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f",
                              htfName, ltfName, htfPat, ltfPat,
                              s.unique_htf_waves, s.total_ltf_trades, s.AvgTrades(),
                              s.Pct1R(), s.Pct2R(), s.Pct3R(), s.Pct4R(), s.PctHTF(), s.PctSL());
   FileWrite(csvHandle, line);
  }

//+------------------------------------------------------------------+
//  Motor Matriz Continua
//+------------------------------------------------------------------+
void AnalyzeContinuous_Matrix(ENUM_TIMEFRAMES htf, string hName, ENUM_TIMEFRAMES ltf, string lName)
  {
   int limit = MathMin(iBars(_Symbol, ltf) - 2, InpHistoryBars);

   RRStats stats[4][4]; 
   for(int i=0; i<4; i++) for(int j=0; j<4; j++) stats[i][j].Reset();
   
   datetime last_htf_time[4][4]; // Para rastrear olas únicas
   ArrayInitialize(last_htf_time, 0);

   // Iteramos el gráfico LTF hacia el pasado
   for(int i = limit; i >= 1; i--)
     {
      int ltfPat = DetectCRT(ltf, i);
      if(ltfPat == PAT_NONE) continue;

      datetime ltfTime = iTime(_Symbol, ltf, i);
      
      // Consultamos si hay una ola macro viva en este instante
      double htf_target;
      datetime htf_signal_time;
      int htf_pat_type;
      
      int bias = GetActiveHTFState(htf, ltfTime, htf_target, htf_signal_time, htf_pat_type);
      if(bias == 0) continue; // Si no hay ola activa macro, ignoramos el trade LTF

      // FILTRO DE ALINEACIÓN CONTINUA: Tomamos trades a favor de la ola macro
      if((bias == 1 && IsBull(ltfPat)) || (bias == -1 && IsBear(ltfPat)))
        {
         // Contabilizar olas únicas
         if(htf_signal_time != last_htf_time[htf_pat_type][ltfPat])
           {
            stats[htf_pat_type][ltfPat].unique_htf_waves++;
            last_htf_time[htf_pat_type][ltfPat] = htf_signal_time;
           }
           
         ResolveContinuousRR(ltf, i, ltfPat, htf_target, stats[htf_pat_type][ltfPat]);
        }
     }

   for(int p1 = 0; p1 < 4; p1++)
     {
      for(int pL = 0; pL < 4; pL++)
        {
         if(stats[p1][pL].total_ltf_trades > 0)
           {
            WriteRRLine(hName, lName, GetPatName(p1), GetPatName(pL), stats[p1][pL]);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//  MAIN
//+------------------------------------------------------------------+
void OnStart()
  {
   g_pip = (_Digits == 5 || _Digits == 3) ? _Point * 10 : _Point;
   
   string filename = StringFormat("CRT_ContinuousRR_Matrix_%s.csv", _Symbol);
   csvHandle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   
   if(csvHandle == INVALID_HANDLE)
     {
      Print("Error al crear el archivo CSV: ", GetLastError());
      return;
     }
     
   FileWrite(csvHandle, "Iman_HTF,Gatillo_LTF,Patron_Macro(Ola),Patron_Micro(Gatillo),Olas_Unicas,Total_Trades_LTF,Media_Trades_por_Ola,Hit_1R_%,Hit_2R_%,Hit_3R_%,Hit_4R_%,Hit_Target_Macro_%,Direct_SL_%");

   Print(">>> CSV Creado. Ejecutando Simulador de Ola Fractal Continua...");
   
   AnalyzeContinuous_Matrix(PERIOD_H12, "H12", PERIOD_H1,  "H1");
   AnalyzeContinuous_Matrix(PERIOD_H12, "H12", PERIOD_M15, "M15");
   
   AnalyzeContinuous_Matrix(PERIOD_H8,  "H8",  PERIOD_H1,  "H1");
   AnalyzeContinuous_Matrix(PERIOD_H8,  "H8",  PERIOD_M15, "M15");
   
   AnalyzeContinuous_Matrix(PERIOD_H4,  "H4",  PERIOD_H1,  "H1");
   AnalyzeContinuous_Matrix(PERIOD_H4,  "H4",  PERIOD_M15, "M15");

   FileClose(csvHandle);
   
   Print("=========================================================");
   Print(" MATRIZ FRACTAL CONTINUA COMPLETADA CON ÉXITO");
   Print(" Archivo guardado: Terminal \\ MQL5 \\ Files \\ ", filename);
   Print("=========================================================");
  }
//+------------------------------------------------------------------+