//+------------------------------------------------------------------+
//|                                              CRT_DailyTester.mq5  |
//|                          Backtest CRT D1 Direction - Sweep & Run  |
//+------------------------------------------------------------------+
#property copyright "CRT Strategy Tester"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

//--- Inputs
input group    "=== Riesgo y Gestión ==="
input double   InpRiskPercent      = 1.0;     // Riesgo % por operación
input long     InpMagicLN          = 660801;  // Magic London
input long     InpMagicNY          = 660802;  // Magic New York

input group    "=== Horarios (hora España) ==="
input int      InpLondonHour       = 8;       // Hora apertura Londres/Frankfurt
input int      InpLondonMinute     = 0;
input int      InpNYHour           = 15;      // Hora apertura NY
input int      InpNYMinute         = 0;
input int      InpCloseHour        = 22;      // Hora cierre forzado
input int      InpCloseMinute      = 50;
input int      InpSpainGMTOffset   = 2;       // Offset España vs GMT (2 invierno, 3 verano aprox; el EA detecta DST)

input group    "=== Logging ==="
input bool     InpWriteCSV         = true;
input string   InpCSVFileName      = "CRT_Results.csv";

input group    "=== Filtros opcionales ==="
input bool     InpEnableSweep      = true;
input bool     InpEnableRun        = true;
input bool     InpEnableLondon     = true;
input bool     InpEnableNY         = true;

//--- Estado diario
struct DailySetup
{
   datetime    day;              // Día D (0:00)
   bool        valid;            // Hay setup válido
   bool        isLong;           // Dirección
   bool        isSweep;          // true=sweep, false=run
   double      tp;
   double      sl;
   bool        tpHitBeforeLN;    // TP alcanzado antes de Londres
   bool        londonExecuted;
   bool        nyExecuted;
   bool        tpHitDuringDay;   // TP alcanzado en algún momento del día D
   double      londonEntry;
   double      nyEntry;
   double      londonResult;     // En R
   double      nyResult;         // En R
   bool        londonClosed;
   bool        nyClosed;
};

DailySetup g_setup;
int        g_fileHandle = INVALID_HANDLE;
datetime   g_lastCheckedDay = 0;

//+------------------------------------------------------------------+
//| Init                                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicLN);
   trade.SetTypeFillingBySymbol(_Symbol);
   symInfo.Name(_Symbol);
   symInfo.RefreshRates();

   ResetSetup();

   if(InpWriteCSV)
   {
      g_fileHandle = FileOpen(InpCSVFileName, FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
      if(g_fileHandle != INVALID_HANDLE)
      {
         FileWrite(g_fileHandle,
            "Fecha","Par","Tipo","Direccion","TP","SL",
            "EntradaLN","ResultadoLN_R","EntradaNY","ResultadoNY_R",
            "TP_Alcanzado","PnL_Dia_R");
      }
   }

   Print("CRT Daily Tester iniciado en ", _Symbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinit                                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Guardar último día si quedó pendiente
   if(g_setup.valid && (g_setup.londonExecuted || g_setup.nyExecuted))
      LogDay();

   if(g_fileHandle != INVALID_HANDLE)
   {
      FileClose(g_fileHandle);
      g_fileHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Reset diario                                                      |
//+------------------------------------------------------------------+
void ResetSetup()
{
   g_setup.day             = 0;
   g_setup.valid           = false;
   g_setup.isLong          = false;
   g_setup.isSweep         = false;
   g_setup.tp              = 0;
   g_setup.sl              = 0;
   g_setup.tpHitBeforeLN   = false;
   g_setup.londonExecuted  = false;
   g_setup.nyExecuted      = false;
   g_setup.tpHitDuringDay  = false;
   g_setup.londonEntry     = 0;
   g_setup.nyEntry         = 0;
   g_setup.londonResult    = 0;
   g_setup.nyResult        = 0;
   g_setup.londonClosed    = false;
   g_setup.nyClosed        = false;
}

//+------------------------------------------------------------------+
//| Devuelve hora España considerando offset del bróker               |
//+------------------------------------------------------------------+
datetime BrokerToSpain(datetime brokerTime)
{
   // El bróker tipicamente está en GMT+2/+3. Calculamos diferencia
   // automáticamente usando TimeGMTOffset.
   datetime gmt = brokerTime - TimeGMTOffset();
   // Aplicar offset España (con DST aproximado: marzo-octubre = +2 GMT_OFFSET? España es GMT+1/+2)
   // España: invierno GMT+1, verano GMT+2
   MqlDateTime dt;
   TimeToStruct(gmt, dt);
   int spainOffset = IsSpainDST(gmt) ? 2 : 1;
   return gmt + spainOffset * 3600;
}

bool IsSpainDST(datetime gmtTime)
{
   // DST Europa: último domingo de marzo a último domingo de octubre
   MqlDateTime dt;
   TimeToStruct(gmtTime, dt);
   if(dt.mon > 3 && dt.mon < 10) return true;
   if(dt.mon < 3 || dt.mon > 10) return false;
   // Marzo y Octubre: aproximación simple (último domingo)
   int lastSunday = LastSundayOfMonth(dt.year, dt.mon);
   if(dt.mon == 3)  return (dt.day > lastSunday) || (dt.day == lastSunday && dt.hour >= 1);
   if(dt.mon == 10) return (dt.day < lastSunday) || (dt.day == lastSunday && dt.hour < 1);
   return false;
}

int LastSundayOfMonth(int year, int month)
{
   int daysInMonth = 31;
   if(month==4||month==6||month==9||month==11) daysInMonth=30;
   if(month==2) daysInMonth = (year%4==0 && (year%100!=0||year%400==0)) ? 29 : 28;
   for(int d = daysInMonth; d >= 22; d--)
   {
      MqlDateTime dt;
      dt.year=year; dt.mon=month; dt.day=d; dt.hour=12; dt.min=0; dt.sec=0;
      datetime t = StructToTime(dt);
      MqlDateTime out;
      TimeToStruct(t, out);
      if(out.day_of_week == 0) return d;
   }
   return daysInMonth;
}

//+------------------------------------------------------------------+
//| Detecta setup CRT en D-1 vs D-2                                   |
//+------------------------------------------------------------------+
bool DetectSetup(datetime today)
{
   double h1 = iHigh(_Symbol, PERIOD_D1, 1);
   double l1 = iLow (_Symbol, PERIOD_D1, 1);
   double c1 = iClose(_Symbol, PERIOD_D1, 1);
   double h2 = iHigh(_Symbol, PERIOD_D1, 2);
   double l2 = iLow (_Symbol, PERIOD_D1, 2);

   if(h1==0 || h2==0) return false;

   ResetSetup();
   g_setup.day = today;

   // --- SWEEP LONG: barre L2, cierra dentro, no saca H2
   if(InpEnableSweep && l1 < l2 && c1 > l2 && h1 <= h2)
   {
      g_setup.valid   = true;
      g_setup.isLong  = true;
      g_setup.isSweep = true;
      g_setup.tp      = h2;
      g_setup.sl      = l1;
      return true;
   }
   // --- SWEEP SHORT
   if(InpEnableSweep && h1 > h2 && c1 < h2 && l1 >= l2)
   {
      g_setup.valid   = true;
      g_setup.isLong  = false;
      g_setup.isSweep = true;
      g_setup.tp      = l2;
      g_setup.sl      = h1;
      return true;
   }
   // --- RUN LONG: cierre por encima de H2
   if(InpEnableRun && c1 > h2)
   {
      g_setup.valid   = true;
      g_setup.isLong  = true;
      g_setup.isSweep = false;
      g_setup.tp      = h1;
      g_setup.sl      = l1;
      return true;
   }
   // --- RUN SHORT: cierre por debajo de L2
   if(InpEnableRun && c1 < l2)
   {
      g_setup.valid   = true;
      g_setup.isLong  = false;
      g_setup.isSweep = false;
      g_setup.tp      = l1;
      g_setup.sl      = h1;
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Comprueba si el TP fue alcanzado durante hoy hasta ahora          |
//+------------------------------------------------------------------+
bool TPAlreadyHitToday()
{
   double dayHigh = iHigh(_Symbol, PERIOD_D1, 0);
   double dayLow  = iLow (_Symbol, PERIOD_D1, 0);

   if(g_setup.isLong)  return (dayHigh >= g_setup.tp);
   else                return (dayLow  <= g_setup.tp);
}

//+------------------------------------------------------------------+
//| Calcula lotaje según riesgo                                       |
//+------------------------------------------------------------------+
double CalcLot(double entryPrice, double stopPrice)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;
   double slDistance= MathAbs(entryPrice - stopPrice);
   if(slDistance <= 0) return 0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0 || tickValue <= 0) return 0;

   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0) return 0;

   double lot = riskMoney / lossPerLot;

   // Normalizar
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(lotMin, MathMin(lotMax, lot));
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Abrir operación                                                   |
//+------------------------------------------------------------------+
bool OpenTrade(bool isLondon)
{
   symInfo.RefreshRates();
   double price = g_setup.isLong ? symInfo.Ask() : symInfo.Bid();
   double sl    = g_setup.sl;
   double tp    = g_setup.tp;
   double lot   = CalcLot(price, sl);
   if(lot <= 0)
   {
      Print("Lote inválido, no se abre operación");
      return false;
   }

   long magic = isLondon ? InpMagicLN : InpMagicNY;
   trade.SetExpertMagicNumber(magic);

   string comment = isLondon ? "CRT_LN" : "CRT_NY";
   bool ok;
   if(g_setup.isLong)
      ok = trade.Buy(lot, _Symbol, price, sl, tp, comment);
   else
      ok = trade.Sell(lot, _Symbol, price, sl, tp, comment);

   if(ok)
   {
      if(isLondon){ g_setup.londonExecuted = true; g_setup.londonEntry = price; }
      else        { g_setup.nyExecuted     = true; g_setup.nyEntry     = price; }
      PrintFormat("Operación abierta %s | %s | Lot=%.2f | Entry=%.5f SL=%.5f TP=%.5f",
                  comment, g_setup.isLong?"LONG":"SHORT", lot, price, sl, tp);
   }
   else
   {
      PrintFormat("Error al abrir %s: %s", comment, trade.ResultRetcodeDescription());
   }
   return ok;
}

//+------------------------------------------------------------------+
//| Cerrar todas las operaciones del EA                               |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      long mg = posInfo.Magic();
      if(mg != InpMagicLN && mg != InpMagicNY) continue;
      trade.SetExpertMagicNumber(mg);
      trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Calcula resultado en R de una posición cerrada                    |
//+------------------------------------------------------------------+
double GetClosedResultR(long magic)
{
   // Buscamos en el historial deals del día
   datetime from = iTime(_Symbol, PERIOD_D1, 0);
   datetime to   = TimeCurrent() + 60;
   if(!HistorySelect(from, to)) return 0;

   double profit = 0;
   double entryPrice = 0;
   double slPrice    = 0;
   bool   found = false;

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magic) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      profit += HistoryDealGetDouble(ticket, DEAL_PROFIT)
              + HistoryDealGetDouble(ticket, DEAL_SWAP)
              + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      found = true;
   }
   if(!found) return 0;

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   if(riskMoney <= 0) return 0;
   return profit / riskMoney;
}

//+------------------------------------------------------------------+
//| ¿Posición abierta con magic?                                      |
//+------------------------------------------------------------------+
bool HasOpenPosition(long magic)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.Magic() == magic) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Log del día al CSV                                                |
//+------------------------------------------------------------------+
void LogDay()
{
   if(!InpWriteCSV || g_fileHandle == INVALID_HANDLE) return;
   if(!g_setup.valid) return;

   string tipo  = g_setup.isSweep ? "SWEEP" : "RUN";
   string dir   = g_setup.isLong  ? "LONG"  : "SHORT";
   string tpHit = g_setup.tpHitDuringDay ? "SI" : "NO";
   double pnl   = g_setup.londonResult + g_setup.nyResult;

   FileWrite(g_fileHandle,
      TimeToString(g_setup.day, TIME_DATE),
      _Symbol,
      tipo,
      dir,
      DoubleToString(g_setup.tp, _Digits),
      DoubleToString(g_setup.sl, _Digits),
      g_setup.londonExecuted ? DoubleToString(g_setup.londonEntry,_Digits) : "-",
      g_setup.londonExecuted ? DoubleToString(g_setup.londonResult,2)      : "-",
      g_setup.nyExecuted     ? DoubleToString(g_setup.nyEntry,_Digits)     : "-",
      g_setup.nyExecuted     ? DoubleToString(g_setup.nyResult,2)          : "-",
      tpHit,
      DoubleToString(pnl,2));
   FileFlush(g_fileHandle);
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime brokerNow = TimeCurrent();
   datetime spainNow  = BrokerToSpain(brokerNow);

   MqlDateTime sp;
   TimeToStruct(spainNow, sp);

   // Día actual del bróker (referencia para velas D1)
   datetime today = iTime(_Symbol, PERIOD_D1, 0);

   // --- Nuevo día: detectar setup ---
   if(today != g_lastCheckedDay)
   {
      // Antes de resetear, loguear el día anterior si existe
      if(g_setup.valid && g_setup.day != 0)
         LogDay();

      g_lastCheckedDay = today;
      DetectSetup(today);
      if(g_setup.valid)
      {
         PrintFormat("[%s] Setup detectado: %s %s | TP=%.5f SL=%.5f",
                     TimeToString(today,TIME_DATE),
                     g_setup.isSweep?"SWEEP":"RUN",
                     g_setup.isLong?"LONG":"SHORT",
                     g_setup.tp, g_setup.sl);
      }
   }

   if(!g_setup.valid) return;

   // Solo en días laborables (evitar fines de semana)
   if(sp.day_of_week == 0 || sp.day_of_week == 6) return;

   // Marcar si TP se ha alcanzado en algún momento del día
   if(!g_setup.tpHitDuringDay)
   {
      double dayHigh = iHigh(_Symbol, PERIOD_D1, 0);
      double dayLow  = iLow (_Symbol, PERIOD_D1, 0);
      if(g_setup.isLong  && dayHigh >= g_setup.tp) g_setup.tpHitDuringDay = true;
      if(!g_setup.isLong && dayLow  <= g_setup.tp) g_setup.tpHitDuringDay = true;
   }

   int currentMin = sp.hour * 60 + sp.min;
   int lnMin      = InpLondonHour * 60 + InpLondonMinute;
   int nyMin      = InpNYHour     * 60 + InpNYMinute;
   int closeMin   = InpCloseHour  * 60 + InpCloseMinute;

   // --- Apertura Londres ---
   if(InpEnableLondon && !g_setup.londonExecuted && currentMin >= lnMin && currentMin < nyMin)
   {
      // Filtro: TP ya cogido antes
      if(TPAlreadyHitToday())
      {
         g_setup.tpHitBeforeLN = true;
         g_setup.londonExecuted = true; // marcamos como "procesado" para no reintentar
         Print("TP ya alcanzado antes de Londres. No se opera.");
      }
      else
      {
         OpenTrade(true);
      }
   }

   // --- Apertura NY ---
   if(InpEnableNY && !g_setup.nyExecuted && currentMin >= nyMin && currentMin < closeMin)
   {
      if(g_setup.tpHitDuringDay)
      {
         g_setup.nyExecuted = true; // procesado, no operamos
         Print("TP ya alcanzado antes de NY. No se opera.");
      }
      else
      {
         OpenTrade(false);
      }
   }

   // --- Cierre forzado fin de día ---
   if(currentMin >= closeMin)
   {
      // Capturar resultados antes de cerrar
      if(HasOpenPosition(InpMagicLN) || HasOpenPosition(InpMagicNY))
      {
         CloseAllPositions();
         Sleep(200);
      }
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: capturamos cierres                            |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long   magic  = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string sym    = HistoryDealGetString (trans.deal, DEAL_SYMBOL);
   long   entry  = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   if(sym != _Symbol) return;
   if(magic != InpMagicLN && magic != InpMagicNY) return;
   if(entry != DEAL_ENTRY_OUT) return; // solo cierres

   if(magic == InpMagicLN && !g_setup.londonClosed)
   {
      g_setup.londonResult = GetClosedResultR(InpMagicLN);
      g_setup.londonClosed = true;
   }
   if(magic == InpMagicNY && !g_setup.nyClosed)
   {
      g_setup.nyResult = GetClosedResultR(InpMagicNY);
      g_setup.nyClosed = true;
   }
}
//+------------------------------------------------------------------+