//+------------------------------------------------------------------+
//|                                     CRT_JSON_Exporter.mq5        |
//|  Exporta setups de CRT en formato JSON Lines para la API Node.js |
//+------------------------------------------------------------------+
#property copyright "Trader Cuantitativo"
#property version   "1.00"
#property script_show_inputs

input int    InpHistoryBars = 5000;   // Velas históricas a analizar
input double InpMinPips     = 5.0;    // Tamaño mínimo de la Vela Base

double g_pip;
int fileHandle;

// Reemplaza partes de la cadena para asegurar JSON válido (aunque aquí no usaremos caracteres raros)
string FormatDateTime(datetime time)
  {
   MqlDateTime dt;
   TimeToStruct(time, dt);
   return StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ", dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
  }

void AnalyzeTimeframe(ENUM_TIMEFRAMES tf, string tfString)
  {
   int limit = MathMin(iBars(_Symbol, tf) - 2, InpHistoryBars);
   if(limit <= 0) return;

   int i = limit;

   while(i >= 1)
     {
      double baseH = iHigh(_Symbol, tf, i);
      double baseL = iLow(_Symbol, tf, i);
      datetime baseTime = iTime(_Symbol, tf, i);
      
      if(baseH - baseL < InpMinPips * g_pip) { i--; continue; }

      int state = 0; 
      int sweeps = 0;
      double currentSL = 0, targetFull = 0, target50 = 0, triggerExtreme = 0;
      bool has_restarted = false;
      bool hit_50_percent = false;
      int break_k = -1; 
      
      datetime entry_time = 0;
      string direction = "";
      string result_type = "";

      for(int k = i - 1; k >= 0; k--)
        {
         double cH = iHigh(_Symbol, tf, k);
         double cL = iLow(_Symbol, tf, k);
         double cC = iClose(_Symbol, tf, k);
         double cO = iOpen(_Symbol, tf, k);
         datetime cTime = iTime(_Symbol, tf, k);

         // === ESTADO 0: ESPERANDO ACTIVACIÓN ===
         if(state == 0)
           {
            if(cC > baseH || cC < baseL) { break_k = k; break; }

            // BARRIDA ALCISTA (BULL)
            if(cL < baseL && cC >= baseL && cC <= baseH)
              {
               state = 1; sweeps = 1; has_restarted = false; hit_50_percent = false;
               currentSL = cL; targetFull = baseH; triggerExtreme = cH;
               target50 = baseL + (baseH - baseL) * 0.5;
               entry_time = cTime;
               direction = "BULL";
               
               if(cH >= target50) hit_50_percent = true;
               
               if(cH >= targetFull) 
                 { 
                  result_type = "TP_EXPANSION"; 
                  break_k = k; break; 
                 }
              }
            // BARRIDA BAJISTA (BEAR)
            else if(cH > baseH && cC <= baseH && cC >= baseL)
              {
               state = -1; sweeps = 1; has_restarted = false; hit_50_percent = false;
               currentSL = cH; targetFull = baseL; triggerExtreme = cL; 
               target50 = baseH - (baseH - baseL) * 0.5;
               entry_time = cTime;
               direction = "BEAR";
               
               if(cL <= target50) hit_50_percent = true;
               
               if(cL <= targetFull) 
                 { 
                  result_type = "TP_EXPANSION";
                  break_k = k; break; 
                 }
              }
           }
           
         // === ESTADO 1: BULLISH ACTIVO ===
         else if(state == 1)
           {
            if(cH >= target50) hit_50_percent = true;

            bool isTP = (cH >= targetFull);
            bool isSL = (cL <= currentSL);

            if(isTP && isSL) { if(MathAbs(cO - currentSL) <= MathAbs(targetFull - cO)) isTP = false; else isSL = false; }

            if(isTP)
              {
               result_type = has_restarted ? "TP_REINICIO" : "TP_EXPANSION";
               break_k = k; break;
              }
            else if(isSL)
              {
               if(cC >= baseL && cC <= baseH) 
                 { 
                  sweeps++; currentSL = cL; triggerExtreme = MathMax(triggerExtreme, cH); has_restarted = false; 
                  if(cH >= target50) hit_50_percent = true;
                 } 
               else 
                 { 
                  result_type = "SL";
                  break_k = k; break; 
                 } 
              }
            else if(!has_restarted)
              {
               if(cH > triggerExtreme && cC < triggerExtreme) has_restarted = true; // Trampa bajista (Reinicio)
              }
           }
           
         // === ESTADO -1: BEARISH ACTIVO ===
         else if(state == -1)
           {
            if(cL <= target50) hit_50_percent = true;

            bool isTP = (cL <= targetFull);
            bool isSL = (cH >= currentSL);

            if(isTP && isSL) { if(MathAbs(cO - currentSL) <= MathAbs(cO - targetFull)) isTP = false; else isSL = false; }

            if(isTP)
              {
               result_type = has_restarted ? "TP_REINICIO" : "TP_EXPANSION";
               break_k = k; break;
              }
            else if(isSL)
              {
               if(cC <= baseH && cC >= baseL) 
                 { 
                  sweeps++; currentSL = cH; triggerExtreme = MathMin(triggerExtreme, cL); has_restarted = false; 
                  if(cL <= target50) hit_50_percent = true;
                 }
               else 
                 { 
                  result_type = "SL";
                  break_k = k; break; 
                 }
              }
            else if(!has_restarted)
              {
               if(cL < triggerExtreme && cC > triggerExtreme) has_restarted = true; // Trampa alcista (Reinicio)
              }
           }
        }

      // Si se completó el setup, escribir el JSON
      if(state != 0 && result_type != "")
        {
         datetime exit_time = iTime(_Symbol, tf, MathMax(0, break_k));
         
         string json = StringFormat(
            "{\"symbol\":\"%s\",\"timeframe\":\"%s\",\"direction\":\"%s\",\"entry_time\":\"%s\",\"exit_time\":\"%s\",\"base_high\":%f,\"base_low\":%f,\"trigger_extreme\":%f,\"sweep_count\":%d,\"has_restarted\":%s,\"hit_50_percent\":%s,\"result_type\":\"%s\",\"mae\":0,\"mfe\":0,\"htf_context\":{},\"metadata\":{\"source\":\"MT5_Batch\"}}",
            _Symbol, tfString, direction, FormatDateTime(entry_time), FormatDateTime(exit_time),
            baseH, baseL, triggerExtreme, sweeps, has_restarted ? "true" : "false", hit_50_percent ? "true" : "false", result_type
         );
         
         FileWrite(fileHandle, json);
        }

      if(break_k != -1) i = break_k; else i--;
     }
  }

void OnStart()
  {
   g_pip = (_Digits == 5 || _Digits == 3) ? _Point * 10 : _Point;
   
   string fileName = "CRT_Export_" + _Symbol + ".jsonl";
   fileHandle = FileOpen(fileName, FILE_WRITE|FILE_TXT|FILE_ANSI);
   
   if(fileHandle == INVALID_HANDLE)
     {
      Print("Error abriendo el archivo para escribir: ", fileName);
      return;
     }

   Print("Extrayendo datos de CRT a JSON Lines...");

   // Temporalidades a extraer
   ENUM_TIMEFRAMES timeframes[] = {PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   string tfNames[] = {"M15", "H1", "H4", "D1"};

   for(int i = 0; i < ArraySize(timeframes); i++) AnalyzeTimeframe(timeframes[i], tfNames[i]);
   
   FileClose(fileHandle);
   Print("Exportación finalizada. Archivo: MQL5/Files/", fileName);
  }
//+------------------------------------------------------------------+