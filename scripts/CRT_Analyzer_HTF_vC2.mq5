//+------------------------------------------------------------------+
//|                                  CRT_BiasAnalyzer_V4_CSV.mq5     |
//|  Exportación Total a CSV: 0, 1, 2 y 3 HTFs (Matriz Completa)     |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "4.00"
#property script_show_inputs

input datetime InpStartDate = D'2020.01.01'; // Fecha de inicio para análisis
input double InpMinPips     = 5.0;   // Filtro: Tamaño mínimo del rango (Pips)

int csvHandle = INVALID_HANDLE;
double g_pip;

//+------------------------------------------------------------------+
//  STRUCT: Acumulador de estadísticas
//+------------------------------------------------------------------+
struct PatternStats
  {
   int    total;
   int    win;
   int    sl;
   int    rev;

   void   Reset()    { total = 0; win = 0; sl = 0; rev = 0; }
   double WinPct()   { return total > 0 ? (double)win / total * 100.0 : 0.0; }
   double SLPct()    { return total > 0 ? (double)sl  / total * 100.0 : 0.0; }
   double RevPct()   { return total > 0 ? (double)rev / total * 100.0 : 0.0; }
   void   Add(int r) { total++; if(r == 1) win++; else if(r == -1) rev++; else sl++; }
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

int ResolveCRT(ENUM_TIMEFRAMES tf, int bar, int pat)
  {
   double mbH, mbL, bearSweepLvl, bullSweepLvl;
   GetMotherBarLevels(tf, bar, mbH, mbL, bearSweepLvl, bullSweepLvl);

   double pR = mbH - mbL;
   bool   buy = (pat == PAT_BULL_SWEEP || pat == PAT_BULL_RUN);
   double sl, tp;

   switch(pat)
     {
      case PAT_BULL_SWEEP: sl = iLow(_Symbol, tf, bar); tp = mbL + pR * 0.5; break;
      case PAT_BEAR_SWEEP: sl = iHigh(_Symbol, tf, bar); tp = mbH - pR * 0.5; break;
      case PAT_BULL_RUN:   sl = iLow(_Symbol, tf, bar); tp = MathMax(mbH + pR * 0.618, iHigh(_Symbol, tf, bar)); break;
      default:             sl = iHigh(_Symbol, tf, bar); tp = MathMin(mbL - pR * 0.618, iLow(_Symbol, tf, bar)); break;
     }

   for(int j = bar - 1; j >= 0; j--)
     {
      double fH  = iHigh (_Symbol, tf, j);
      double fL  = iLow  (_Symbol, tf, j);
      double fC  = iClose(_Symbol, tf, j);

      double oppMbH, oppMbL, oppBearSweep, oppBullSweep;
      GetMotherBarLevels(tf, j, oppMbH, oppMbL, oppBearSweep, oppBullSweep);
      double oppR = oppMbH - oppMbL;

      if(buy)
        {
         if(fL < sl)  return 0;   
         if(fH >= tp) return 1;   
         if(oppR >= InpMinPips * g_pip)
           {
            if(fH > oppBearSweep && fC < oppBearSweep) return -1; 
            if(fL < oppBullSweep && fC < oppBullSweep) return -1; 
           }
        }
      else
        {
         if(fH > sl)  return 0;   
         if(fL <= tp) return 1;   
         if(oppR >= InpMinPips * g_pip)
           {
            if(fL < oppBullSweep && fC > oppBullSweep)  return -1; 
            if(fH > oppBearSweep && fC > oppBearSweep)  return -1; 
           }
        }
     }
   return 0; 
  }

//+------------------------------------------------------------------+
//  Escritura en CSV
//+------------------------------------------------------------------+
void WriteCSVLine(string type, string htfNames, string ltfName, string htfPat, string ltfPat, string align, PatternStats &s, PatternStats &base)
  {
   if(s.total == 0) return;
   double delta = s.WinPct() - base.WinPct();
   string line = StringFormat("%s,%s,%s,%s,%s,%s,%d,%.1f,%.1f,%.1f,%.1f",
                              type, htfNames, ltfName, htfPat, ltfPat, align,
                              s.total, s.WinPct(), s.SLPct(), s.RevPct(), delta);
   FileWrite(csvHandle, line);
  }

//+------------------------------------------------------------------+
//  NIVEL 0: Baseline
//+------------------------------------------------------------------+
void ComputeAndExportBaseline(ENUM_TIMEFRAMES tf, string tfName, PatternStats &base[])
  {
   for(int p = 0; p < 4; p++) base[p].Reset();
   int limit = MathMin(iBars(_Symbol, tf) - 2, iBarShift(_Symbol, tf, InpStartDate));
   for(int i = limit; i >= 1; i--)
     {
      int pat = DetectCRT(tf, i);
      if(pat == PAT_NONE) continue;
      int result = ResolveCRT(tf, i, pat);
      base[pat].Add(result);
     }
     
   for(int p = 0; p < 4; p++)
     {
      if(base[p].total > 0)
         WriteCSVLine("0_BASE", "NONE", tfName, "NONE", GetPatName(p), "BASELINE", base[p], base[p]); // Delta 0.0
     }
  }

//+------------------------------------------------------------------+
//  NIVEL 1: Single Bias (1 HTF)
//+------------------------------------------------------------------+
void AnalyzeSingleBias(ENUM_TIMEFRAMES htf, string hName, ENUM_TIMEFRAMES ltf, string ltfName, PatternStats &base[])
  {
   int hTotal = iBars(_Symbol, htf);
   int limit  = MathMin(iBars(_Symbol, ltf) - 2, iBarShift(_Symbol, ltf, InpStartDate));

   PatternStats stats[4][4]; // [patHTF][patLTF]
   for(int i=0; i<4; i++) for(int j=0; j<4; j++) stats[i][j].Reset();

   for(int i = limit; i >= 1; i--)
     {
      int ltfPat = DetectCRT(ltf, i);
      if(ltfPat == PAT_NONE) continue;

      datetime ltfTime = iTime(_Symbol, ltf, i);
      int hIdx = iBarShift(_Symbol, htf, ltfTime);
      if(hIdx + 2 >= hTotal) continue;
      int hPat = DetectCRT(htf, hIdx + 1);
      if(hPat == PAT_NONE) continue;

      int result = ResolveCRT(ltf, i, ltfPat);
      stats[hPat][ltfPat].Add(result);
     }

   for(int p1 = 0; p1 < 4; p1++)
     {
      for(int pL = 0; pL < 4; pL++)
        {
         if(stats[p1][pL].total == 0) continue;
         string alignStr = (IsBull(p1) == IsBull(pL)) ? "ALINEADO" : "COUNTER";
         WriteCSVLine("1_SINGLE", hName, ltfName, GetPatName(p1), GetPatName(pL), alignStr, stats[p1][pL], base[pL]);
        }
     }
  }

//+------------------------------------------------------------------+
//  NIVEL 2: Double Bias (2 HTFs)
//+------------------------------------------------------------------+
void AnalyzeDoubleBias(ENUM_TIMEFRAMES htf1, string h1Name, ENUM_TIMEFRAMES htf2, string h2Name, ENUM_TIMEFRAMES ltf, string ltfName, PatternStats &base[])
  {
   int h1Total = iBars(_Symbol, htf1);
   int h2Total = iBars(_Symbol, htf2);
   int limit   = MathMin(iBars(_Symbol, ltf) - 2, InpHistoryBars);

   PatternStats stats[4][4][4];
   for(int i=0; i<4; i++) for(int j=0; j<4; j++) for(int k=0; k<4; k++) stats[i][j][k].Reset();

   for(int i = limit; i >= 1; i--)
     {
      int ltfPat = DetectCRT(ltf, i);
      if(ltfPat == PAT_NONE) continue;

      datetime ltfTime = iTime(_Symbol, ltf, i);

      int h1Idx = iBarShift(_Symbol, htf1, ltfTime);
      if(h1Idx + 2 >= h1Total) continue;
      int h1Pat = DetectCRT(htf1, h1Idx + 1);
      if(h1Pat == PAT_NONE) continue;

      int h2Idx = iBarShift(_Symbol, htf2, ltfTime);
      if(h2Idx + 2 >= h2Total) continue;
      int h2Pat = DetectCRT(htf2, h2Idx + 1);
      if(h2Pat == PAT_NONE) continue;

      int result = ResolveCRT(ltf, i, ltfPat);
      stats[h1Pat][h2Pat][ltfPat].Add(result);
     }

   string comboName = h1Name + "+" + h2Name;
   for(int p1 = 0; p1 < 4; p1++)
     {
      for(int p2 = 0; p2 < 4; p2++)
        {
         for(int pL = 0; pL < 4; pL++)
           {
            if(stats[p1][p2][pL].total == 0) continue;
            
            bool h1B = IsBull(p1); bool h2B = IsBull(p2); bool lB = IsBull(pL);
            string alignStr = "MIXED_HTF"; 
            if(h1B == h2B) { alignStr = (h1B == lB) ? "ALINEADO" : "COUNTER"; }

            string patHCombo = GetPatName(p1) + " + " + GetPatName(p2);
            WriteCSVLine("2_DOUBLE", comboName, ltfName, patHCombo, GetPatName(pL), alignStr, stats[p1][p2][pL], base[pL]);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//  NIVEL 3: Triple Bias (3 HTFs)
//+------------------------------------------------------------------+
void AnalyzeTripleBias(ENUM_TIMEFRAMES htf1, string h1Name, ENUM_TIMEFRAMES htf2, string h2Name, ENUM_TIMEFRAMES htf3, string h3Name, ENUM_TIMEFRAMES ltf, string ltfName, PatternStats &base[])
  {
   int h1Total = iBars(_Symbol, htf1);
   int h2Total = iBars(_Symbol, htf2);
   int h3Total = iBars(_Symbol, htf3);
   int limit   = MathMin(iBars(_Symbol, ltf) - 2, InpHistoryBars);

   PatternStats stats[4][4][4][4]; // [h1][h2][h3][ltf]
   for(int i=0; i<4; i++) for(int j=0; j<4; j++) for(int k=0; k<4; k++) for(int l=0; l<4; l++) stats[i][j][k][l].Reset();

   for(int i = limit; i >= 1; i--)
     {
      int ltfPat = DetectCRT(ltf, i);
      if(ltfPat == PAT_NONE) continue;

      datetime ltfTime = iTime(_Symbol, ltf, i);

      int h1Idx = iBarShift(_Symbol, htf1, ltfTime);
      if(h1Idx + 2 >= h1Total) continue;
      int h1Pat = DetectCRT(htf1, h1Idx + 1);
      if(h1Pat == PAT_NONE) continue;

      int h2Idx = iBarShift(_Symbol, htf2, ltfTime);
      if(h2Idx + 2 >= h2Total) continue;
      int h2Pat = DetectCRT(htf2, h2Idx + 1);
      if(h2Pat == PAT_NONE) continue;
      
      int h3Idx = iBarShift(_Symbol, htf3, ltfTime);
      if(h3Idx + 2 >= h3Total) continue;
      int h3Pat = DetectCRT(htf3, h3Idx + 1);
      if(h3Pat == PAT_NONE) continue;

      int result = ResolveCRT(ltf, i, ltfPat);
      stats[h1Pat][h2Pat][h3Pat][ltfPat].Add(result);
     }

   string comboName = h1Name + "+" + h2Name + "+" + h3Name;
   for(int p1 = 0; p1 < 4; p1++)
     {
      for(int p2 = 0; p2 < 4; p2++)
        {
         for(int p3 = 0; p3 < 4; p3++)
           {
            for(int pL = 0; pL < 4; pL++)
              {
               if(stats[p1][p2][p3][pL].total == 0) continue;
               
               bool h1B = IsBull(p1); bool h2B = IsBull(p2); bool h3B = IsBull(p3); bool lB = IsBull(pL);
               string alignStr = "MIXED_HTF"; 
               
               // Si los 3 apuntan al mismo sitio
               if(h1B == h2B && h2B == h3B) { alignStr = (h1B == lB) ? "ALINEADO" : "COUNTER"; }

               string patHCombo = GetPatName(p1) + " + " + GetPatName(p2) + " + " + GetPatName(p3);
               WriteCSVLine("3_TRIPLE", comboName, ltfName, patHCombo, GetPatName(pL), alignStr, stats[p1][p2][p3][pL], base[pL]);
              }
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
   
   string filename = StringFormat("CRT_FullMatrix_%s.csv", _Symbol);
   csvHandle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   
   if(csvHandle == INVALID_HANDLE)
     {
      Print("Error al crear el archivo CSV: ", GetLastError());
      return;
     }
     
   FileWrite(csvHandle, "Type,HTF_Source,LTF_Target,HTF_Patterns,LTF_Pattern,Alignment,Trades,Win_Pct,SL_Pct,Rev_Pct,Delta_vs_Base");

   Print(">>> CSV Creado. Calculando Nivel 0 (Baselines)...");
   PatternStats bW1[4], bD1[4], bH12[4], bH8[4], bH4[4];
   
   ComputeAndExportBaseline(PERIOD_W1,  "W1",  bW1);
   ComputeAndExportBaseline(PERIOD_D1,  "D1",  bD1);
   ComputeAndExportBaseline(PERIOD_H12, "H12", bH12);
   ComputeAndExportBaseline(PERIOD_H8,  "H8",  bH8);
   ComputeAndExportBaseline(PERIOD_H4,  "H4",  bH4);

   Print(">>> Ejecutando Nivel 1 (Single Bias)...");
   AnalyzeSingleBias(PERIOD_MN1, "MN1", PERIOD_W1,  "W1",  bW1);
   AnalyzeSingleBias(PERIOD_MN1, "MN1", PERIOD_D1,  "D1",  bD1);
   AnalyzeSingleBias(PERIOD_MN1, "MN1", PERIOD_H12, "H12", bH12);
   AnalyzeSingleBias(PERIOD_MN1, "MN1", PERIOD_H8,  "H8",  bH8);
   AnalyzeSingleBias(PERIOD_MN1, "MN1", PERIOD_H4,  "H4",  bH4);
   
   AnalyzeSingleBias(PERIOD_W1, "W1", PERIOD_D1,  "D1",  bD1);
   AnalyzeSingleBias(PERIOD_W1, "W1", PERIOD_H12, "H12", bH12);
   AnalyzeSingleBias(PERIOD_W1, "W1", PERIOD_H8,  "H8",  bH8);
   AnalyzeSingleBias(PERIOD_W1, "W1", PERIOD_H4,  "H4",  bH4);
   
   AnalyzeSingleBias(PERIOD_D1, "D1", PERIOD_H12, "H12", bH12);
   AnalyzeSingleBias(PERIOD_D1, "D1", PERIOD_H8,  "H8",  bH8);
   AnalyzeSingleBias(PERIOD_D1, "D1", PERIOD_H4,  "H4",  bH4);

   Print(">>> Ejecutando Nivel 2 (Double Bias)...");
   AnalyzeDoubleBias(PERIOD_MN1, "MN1", PERIOD_W1, "W1", PERIOD_D1,  "D1",  bD1);
   AnalyzeDoubleBias(PERIOD_MN1, "MN1", PERIOD_W1, "W1", PERIOD_H12, "H12", bH12);
   AnalyzeDoubleBias(PERIOD_MN1, "MN1", PERIOD_W1, "W1", PERIOD_H8,  "H8",  bH8);
   AnalyzeDoubleBias(PERIOD_MN1, "MN1", PERIOD_W1, "W1", PERIOD_H4,  "H4",  bH4);

   AnalyzeDoubleBias(PERIOD_W1, "W1", PERIOD_D1, "D1", PERIOD_H12, "H12", bH12);
   AnalyzeDoubleBias(PERIOD_W1, "W1", PERIOD_D1, "D1", PERIOD_H8,  "H8",  bH8);
   AnalyzeDoubleBias(PERIOD_W1, "W1", PERIOD_D1, "D1", PERIOD_H4,  "H4",  bH4);

   Print(">>> Ejecutando Nivel 3 (Triple Bias)...");
   AnalyzeTripleBias(PERIOD_MN1, "MN1", PERIOD_W1, "W1", PERIOD_D1, "D1", PERIOD_H12, "H12", bH12);
   AnalyzeTripleBias(PERIOD_MN1, "MN1", PERIOD_W1, "W1", PERIOD_D1, "D1", PERIOD_H8,  "H8",  bH8);
   AnalyzeTripleBias(PERIOD_MN1, "MN1", PERIOD_W1, "W1", PERIOD_D1, "D1", PERIOD_H4,  "H4",  bH4);

   FileClose(csvHandle);
   
   Print("=========================================================");
   Print(" EXPORTACIÓN DE MATRIZ COMPLETA FINALIZADA");
   Print(" Archivo guardado: Terminal \\ MQL5 \\ Files \\ ", filename);
   Print("=========================================================");
  }
//+------------------------------------------------------------------+
