//+------------------------------------------------------------------+
//|                                              CRT_Dashboard_v4.mq5|
//|        Panel Profesional: Con Fondo y Multi-TF en Vivo           |
//+------------------------------------------------------------------+
#property copyright "Iván Megias Duran"
#property version   "4.00"
#property indicator_chart_window
#property indicator_plots 0

input double InpMinPips = 1.0;     // Filtro de pips (bajado para mayor detección)
input color  InpBGColor = C'20,20,20'; // Color de fondo del panel
input int    InpOpacity = 220;     // Opacidad (0-255)

#define PAT_BULL_SWEEP  0
#define PAT_BEAR_SWEEP  1
#define PAT_BULL_RUN    2
#define PAT_BEAR_RUN    3
#define PAT_NONE       -1

struct MatrixRow {
   string type, ltf_target, htf_pattern, ltf_pattern;
   int trades; double win_pct;
};

MatrixRow db[];
bool matrixLoaded = false;

//+------------------------------------------------------------------+
//  Utilidades de Patrones
//+------------------------------------------------------------------+
string GetPatName(int p) {
   if(p == PAT_BULL_SWEEP) return "Bull Sweep";
   if(p == PAT_BEAR_SWEEP) return "Bear Sweep";
   if(p == PAT_BULL_RUN)   return "Bull Run";
   if(p == PAT_BEAR_RUN)   return "Bear Run";
   return "None";
}

void GetMotherBarLevels(string sym, ENUM_TIMEFRAMES tf, int signalBar, double &mbH, double &mbL, double &bearSweepLvl, double &bullSweepLvl) {
   int limit = iBars(sym, tf) - 1;
   int mbIdx = signalBar + 1;
   if(mbIdx > limit) { mbH = 0; mbL = 0; return; }

   mbH = iHigh(sym, tf, mbIdx); mbL = iLow(sym, tf, mbIdx);
   while(mbIdx < limit) {
      double prevH = iHigh(sym, tf, mbIdx+1); double prevL = iLow(sym, tf, mbIdx+1);
      if(mbH <= prevH && mbL >= prevL) { mbIdx++; mbH = prevH; mbL = prevL; }
      else break;
   }
   bearSweepLvl = iHigh(sym, tf, signalBar + 1);
   bullSweepLvl = iLow(sym, tf, signalBar + 1);
   if(mbIdx != signalBar + 1) {
      double mbOpen = iOpen(sym, tf, mbIdx); double mbClose = iClose(sym, tf, mbIdx);
      if(mbClose < mbOpen) bullSweepLvl = mbL;
      else if(mbClose > mbOpen) bearSweepLvl = mbH; 
      else { bearSweepLvl = mbH; bullSweepLvl = mbL; }
   }
}

int DetectCRT(string sym, ENUM_TIMEFRAMES tf, int bar) {
   // Forzar sincronización de datos
   if(iBars(sym, tf) < 10) return PAT_NONE;

   double mbH, mbL, bearSweepLvl, bullSweepLvl;
   GetMotherBarLevels(sym, tf, bar, mbH, mbL, bearSweepLvl, bullSweepLvl);

   double pnt = SymbolInfoDouble(sym, SYMBOL_POINT);
   int dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double pipValue = (dig == 3 || dig == 5) ? pnt * 10 : pnt;

   if((mbH - mbL) < InpMinPips * pipValue) return PAT_NONE;
   
   double cH = iHigh(sym, tf, bar);
   double cL = iLow(sym, tf, bar);
   double cC = iClose(sym, tf, bar);

   if(cH > bearSweepLvl && cC < bearSweepLvl) return PAT_BEAR_SWEEP;
   if(cL < bullSweepLvl && cC > bullSweepLvl) return PAT_BULL_SWEEP;
   if(cH > bearSweepLvl && cC > bearSweepLvl) return PAT_BULL_RUN;
   if(cL < bullSweepLvl && cC < bullSweepLvl) return PAT_BEAR_RUN;
   return PAT_NONE;
}

//+------------------------------------------------------------------+
//  Interfaz Visual Mejorada (Con Fondo)
//+------------------------------------------------------------------+
void DrawRect(string name, int x, int y, int w, int h, color bg) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void DrawLabel(string name, string text, int x, int y, color col, int fontSize = 9, bool bold = false) {
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Consolas");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
}

void UpdatePanel() {
   // Obtener patrones
   string stMN1 = GetPatName(DetectCRT(_Symbol, PERIOD_MN1, 1));
   string stW1  = GetPatName(DetectCRT(_Symbol, PERIOD_W1,  1));
   string stD1  = GetPatName(DetectCRT(_Symbol, PERIOD_D1,  1));
   
   string stH12 = GetPatName(DetectCRT(_Symbol, PERIOD_H12, 0));
   string stH8  = GetPatName(DetectCRT(_Symbol, PERIOD_H8,  0));
   string stH4  = GetPatName(DetectCRT(_Symbol, PERIOD_H4,  0)); 

   string currentHTF = stMN1 + " + " + stW1 + " + " + stD1;
   
   // Dibujar Fondo
   DrawRect("crt_bg", 10, 10, 420, 180, InpBGColor);

   int y = 25;
   DrawLabel("crt_header", "--- CRT EDGE DASHBOARD ---", 410, y, clrWhite, 10, true);
   DrawLabel("crt_sub", "HTF: " + currentHTF, 410, y+=22, clrGold);

   y += 25;
   DrawLabel("h_tf", "TF", 410, y, clrDarkGray);
   DrawLabel("h_pa", "PATRON (LIVE)", 370, y, clrOrange);
   DrawLabel("h_ba", "BASE WR", 240, y, clrDarkGray);
   DrawLabel("h_al", "ALINEADO", 150, y, clrDarkGray);
   DrawLabel("h_tr", "TRADES", 60, y, clrDarkGray);

   string tfs[3] = {"H12", "H8", "H4"};
   string pats[3] = {stH12, stH8, stH4};
   
   for(int i=0; i<3; i++) {
      y += 18;
      double baseWR = -1, aligWR = -1; int trades = 0;
      
      if(matrixLoaded && pats[i] != "None") {
         for(int j=0; j<ArraySize(db); j++) {
            if(db[j].ltf_target == tfs[i] && db[j].ltf_pattern == pats[i]) {
               if(db[j].type == "0_BASE") baseWR = db[j].win_pct;
               else if(db[j].type == "3_TRIPLE" && db[j].htf_pattern == currentHTF) {
                  aligWR = db[j].win_pct; trades = db[j].trades;
               }
            }
         }
      }

      DrawLabel("r_"+tfs[i]+"_1", tfs[i], 410, y, clrDodgerBlue, 10, true);
      DrawLabel("r_"+tfs[i]+"_2", pats[i], 370, y, pats[i]=="None"?clrDimGray:clrWhite);
      DrawLabel("r_"+tfs[i]+"_3", baseWR>=0?DoubleToString(baseWR,1)+"%":"---", 240, y, clrSilver);
      
      color alCol = (aligWR > baseWR) ? clrLimeGreen : (aligWR < baseWR && aligWR >= 0 ? clrLightCoral : clrGray);
      DrawLabel("r_"+tfs[i]+"_4", aligWR>=0?DoubleToString(aligWR,1)+"%":"---", 150, y, alCol, 10, true);
      DrawLabel("r_"+tfs[i]+"_5", IntegerToString(trades), 60, y, clrGray);
   }
}

//+------------------------------------------------------------------+
void LoadMatrix() {
   string filename = "CRT_FullMatrix_" + _Symbol + ".csv";
   int handle = FileOpen(filename, FILE_READ|FILE_CSV|FILE_ANSI, ',');
   if(handle == INVALID_HANDLE) return;
   FileReadString(handle); ArrayResize(db, 0);
   while(!FileIsEnding(handle)) {
      string type = FileReadString(handle); if(type == "") break;
      string htf_src = FileReadString(handle); string ltf_tgt = FileReadString(handle);
      string htf_pat = FileReadString(handle); string ltf_pat = FileReadString(handle);
      FileReadString(handle); // align
      string sTrades = FileReadString(handle); string sWin = FileReadString(handle);
      FileReadString(handle); FileReadString(handle); FileReadString(handle);
      
      if(type == "0_BASE" || (type == "3_TRIPLE" && htf_src == "MN1+W1+D1")) {
         if(ltf_tgt == "H12" || ltf_tgt == "H8" || ltf_tgt == "H4") {
            int size = ArraySize(db); ArrayResize(db, size + 1);
            db[size].type = type; db[size].ltf_target = ltf_tgt;
            db[size].htf_pattern = htf_pat; db[size].ltf_pattern = ltf_pat;
            db[size].trades = (int)StringToInteger(sTrades); db[size].win_pct = StringToDouble(sWin);
         }
      }
   }
   FileClose(handle); matrixLoaded = true;
}

int OnInit() {
   // Forzar carga de historial para TFs raros
   iBars(_Symbol, PERIOD_H12); iBars(_Symbol, PERIOD_H8);
   LoadMatrix(); EventSetTimer(1); return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
   EventKillTimer(); ObjectsDeleteAll(0, "crt_"); ObjectsDeleteAll(0, "h_"); ObjectsDeleteAll(0, "r_");
}

int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[]) {
   return(rates_total);
}

void OnTimer() { UpdatePanel(); ChartRedraw(); }