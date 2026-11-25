//+------------------------------------------------------------------+
//|                                       CRT_TimeTraveler.mq5       |
//|  Extrae el estado de HTFs para una lista de operaciones (Diario) |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "1.00"
#property script_show_inputs

input string InpInputFile   = "Diario_Input.csv";  // Archivo con el diario (en MQL5/Files)
input string InpOutputFile  = "Diario_HTF_State.csv"; // Archivo de salida
input int    InpHoursOffset = 0;                   // Desfase Diario -> Broker (ej: +1 si España es 18h y Broker 19h)
input double InpMinPips     = 5.0;                 // Filtro: Tamaño mínimo del rango (Pips)

// Definiciones de patrones idénticas a tu matriz original
#define PAT_BULL_SWEEP  0
#define PAT_BEAR_SWEEP  1
#define PAT_BULL_RUN    2
#define PAT_BEAR_RUN    3
#define PAT_NONE       -1

string GetPatName(int p)
  {
   if(p == PAT_BULL_SWEEP) return "Bull Sweep";
   if(p == PAT_BEAR_SWEEP) return "Bear Sweep";
   if(p == PAT_BULL_RUN)   return "Bull Run";
   if(p == PAT_BEAR_RUN)   return "Bear Run";
   return "None";
  }

//+------------------------------------------------------------------+
//  Rastreo Estructural (Lógica Original)
//+------------------------------------------------------------------+
void GetMotherBarLevels(string sym, ENUM_TIMEFRAMES tf, int signalBar, double &mbH, double &mbL, double &bearSweepLvl, double &bullSweepLvl)
  {
   int limit = iBars(sym, tf) - 1;
   int mbIdx = signalBar + 1;
   if(mbIdx > limit) { mbH = 0; mbL = 0; bearSweepLvl = 0; bullSweepLvl = 0; return; }

   mbH = iHigh(sym, tf, mbIdx);
   mbL = iLow(sym, tf, mbIdx);
   while(mbIdx < limit)
     {
      double prevH = iHigh(sym, tf, mbIdx+1);
      double prevL = iLow(sym, tf, mbIdx+1);
      if(mbH <= prevH && mbL >= prevL) { mbIdx++; mbH = prevH; mbL = prevL; }
      else break;
     }

   bearSweepLvl = iHigh(sym, tf, signalBar + 1);
   bullSweepLvl = iLow(sym, tf, signalBar + 1);
   if(mbIdx != signalBar + 1)
     {
      double mbOpen = iOpen(sym, tf, mbIdx);
      double mbClose = iClose(sym, tf, mbIdx);
      if(mbClose < mbOpen)      bullSweepLvl = mbL;
      else if(mbClose > mbOpen) bearSweepLvl = mbH; 
      else { bearSweepLvl = mbH; bullSweepLvl = mbL; }
     }
  }

int DetectCRT(string sym, ENUM_TIMEFRAMES tf, int bar)
  {
   int totalBars = iBars(sym, tf);
   if(bar + 1 >= totalBars || bar < 0) return PAT_NONE;

   double mbH, mbL, bearSweepLvl, bullSweepLvl;
   GetMotherBarLevels(sym, tf, bar, mbH, mbL, bearSweepLvl, bullSweepLvl);

   double pipValue = (SymbolInfoInteger(sym, SYMBOL_DIGITS) == 5 || SymbolInfoInteger(sym, SYMBOL_DIGITS) == 3) ? SymbolInfoDouble(sym, SYMBOL_POINT) * 10 : SymbolInfoDouble(sym, SYMBOL_POINT);

   if((mbH - mbL) < InpMinPips * pipValue) return PAT_NONE;
   
   double cH = iHigh (sym, tf, bar);
   double cL = iLow  (sym, tf, bar);
   double cC = iClose(sym, tf, bar);

   if(cH > bearSweepLvl && cC < bearSweepLvl) return PAT_BEAR_SWEEP;
   if(cL < bullSweepLvl && cC > bullSweepLvl) return PAT_BULL_SWEEP;
   if(cH > bearSweepLvl && cC > bearSweepLvl) return PAT_BULL_RUN;
   if(cL < bullSweepLvl && cC < bullSweepLvl) return PAT_BEAR_RUN;

   return PAT_NONE;
  }

//+------------------------------------------------------------------+
//  MAIN
//+------------------------------------------------------------------+
void OnStart()
  {
   int handleIn = FileOpen(InpInputFile, FILE_READ|FILE_CSV|FILE_ANSI, ',');
   if(handleIn == INVALID_HANDLE)
     {
      Print("Error leyendo el archivo de entrada. Código: ", GetLastError());
      return;
     }

   int handleOut = FileOpen(InpOutputFile, FILE_WRITE|FILE_CSV|FILE_ANSI, ',');
   if(handleOut == INVALID_HANDLE)
     {
      Print("Error creando el archivo de salida. Código: ", GetLastError());
      FileClose(handleIn);
      return;
     }

   // Escribir cabeceras
   FileWrite(handleOut, "FechaHora_Diario,Simbolo,Ref,MN1,W1,D1,H12,H8,H4");
   
   // Saltar cabecera del input si existe (asumimos que la primera fila no es fecha válida si falla el parseo)
   string header1 = FileReadString(handleIn);
   string header2 = FileReadString(handleIn);
   string header3 = FileReadString(handleIn);
   
   Print("Procesando diario...");

   while(!FileIsEnding(handleIn))
     {
      string timeStr = FileReadString(handleIn);
      string sym     = FileReadString(handleIn);
      string ref     = FileReadString(handleIn);
      
      if(timeStr == "" || sym == "") continue;

      // Parsear tiempo y aplicar desfase del broker
      datetime diaryTime = StringToTime(timeStr);
      datetime brokerTime = diaryTime + (InpHoursOffset * 3600);
      
      // Extraer estados (+1 para asegurar que leemos la última vela CERRADA antes de esa hora, tal como en la matriz original)
      string stateMN1 = GetPatName(DetectCRT(sym, PERIOD_MN1, iBarShift(sym, PERIOD_MN1, brokerTime) + 1));
      string stateW1  = GetPatName(DetectCRT(sym, PERIOD_W1,  iBarShift(sym, PERIOD_W1,  brokerTime) + 1));
      string stateD1  = GetPatName(DetectCRT(sym, PERIOD_D1,  iBarShift(sym, PERIOD_D1,  brokerTime) + 1));
      string stateH12 = GetPatName(DetectCRT(sym, PERIOD_H12, iBarShift(sym, PERIOD_H12, brokerTime) + 1));
      string stateH8  = GetPatName(DetectCRT(sym, PERIOD_H8,  iBarShift(sym, PERIOD_H8,  brokerTime) + 1));
      string stateH4  = GetPatName(DetectCRT(sym, PERIOD_H4,  iBarShift(sym, PERIOD_H4,  brokerTime) + 1));

      FileWrite(handleOut, timeStr, sym, ref, stateMN1, stateW1, stateD1, stateH12, stateH8, stateH4);
     }

   FileClose(handleIn);
   FileClose(handleOut);
   Print("Proceso finalizado con éxito. Archivo generado: ", InpOutputFile);
  }
//+------------------------------------------------------------------+