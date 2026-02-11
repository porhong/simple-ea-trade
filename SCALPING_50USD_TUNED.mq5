//+------------------------------------------------------------------+
//|                                         SCALPING_50USD_TUNED.mq5 |
//|                    Tuned Scalper for $50 Account                 |
//|                    RELAXED SIGNALS - More Trading Opportunities  |
//+------------------------------------------------------------------+
#property strict
#property version   "5.00"
#property description "XAUUSD Scalper: Tuned for $50 accounts with relaxed signals"
#property description "More entry opportunities, moderate risk management"
#property description "Tuned Edition - Less Strict Filters"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo pos;

//----------------------------
// Inputs - $50 ACCOUNT TUNED
//----------------------------
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M5;
input long            InpMagic            = 20260211;
input bool            InpOnePositionOnly  = true;

// Risk Management (MODERATE for $50)
input double InpFixedLot           = 0.02;    // 0.02 = $50 account suitable
input double InpMaxLot             = 0.03;    // Max 0.03 for $50
input double InpMinLot             = 0.01;

// Daily Protection (Adjusted for $50)
input int    InpMaxDailyLoss       = 3;       // Stop after 3 losses
input int    InpMaxDailyProfit     = 8;       // Stop after 8 wins
input double InpMaxDailyLossDollars = 5.0;    // Hard stop at $5 loss
input double InpMaxDailyProfitDollars = 10.0; // Take profit at $10 gain

// Scalping Stops/Targets (MODERATE)
input int    InpScalpSL_Points     = 150;     // 15 pips (~$1.50-3.00 risk)
input int    InpScalpTP_Points     = 200;     // 20 pips (~$2.00-4.00 profit)
input bool   InpUsePartialTP       = true;
input int    InpPartialTP_Points   = 100;     // Close 50% at 10 pips
input double InpPartialClosePercent = 50.0;

// Spread Filter (RELAXED)
input int    InpMaxSpreadPoints    = 80;      // Allow slightly wider spreads
input int    InpDeviationPoints    = 10;

// Entry Filters (RELAXED - KEY CHANGES)
input int    InpFastEMA            = 8;       // Faster EMA for quicker signals
input int    InpSlowEMA            = 18;      // Tighter EMA spread
input int    InpRSIPeriod          = 12;
input int    InpATRPeriod          = 10;

// === RELAXED FILTER SETTINGS ===
input group "=== RELAXED FILTERS (More Signals) ==="
input bool   InpRequireStrongMomentum = false;   // DISABLED: Was blocking too many trades
input int    InpMomentumPeriod        = 10;
input double InpMinMomentumThreshold  = 0.0003;

input bool   InpRequireTrendAlignment = true;    // Keep but relaxed
input bool   InpAvoidChoppyMarket     = false;   // DISABLED: ADX filter was too strict
input int    InpADXPeriod             = 14;
input double InpMinADX                = 20.0;    // Lowered from 25

input bool   InpRequireRSIConfirmation = true;   // Keep but WIDENED zones
input double InpRSI_BuyMin            = 40.0;    // WIDENED from 50-60
input double InpRSI_BuyMax            = 70.0;    // WIDENED
input double InpRSI_SellMin           = 30.0;    // WIDENED from 40-50
input double InpRSI_SellMax           = 60.0;    // WIDENED

input bool   InpRequirePriceAction    = false;   // DISABLED: Was too strict
input double InpMinCandleBodyPercent  = 30.0;    // Lowered from 50%

input bool   InpRequireEMADistance    = false;   // DISABLED: Was blocking trades
input double InpMinEMADistancePoints  = 10.0;    // Lowered from 20

// NEW: Alternative Entry Methods
input bool   InpUseEMACrossEntry     = true;    // EMA Cross entries
input bool   InpUseRSIBounceEntry    = true;    // RSI bounce from extremes
input bool   InpUseTrendFollowEntry  = true;    // Trend following entries

// Overtrading Protection
input int    InpCooldownSeconds    = 300;       // 5 min cooldown (reduced from 10)
input int    InpMaxTradesPerDay    = 15;        // More trades allowed

// SESSION MANAGEMENT - RELAXED
input group "=== SESSION MANAGEMENT (RELAXED) ==="
input bool   InpUseSessionFilter   = true;
input bool   InpTradeLondon        = true;
input bool   InpTradeLondonNY      = true;      // PEAK SCALPING
input bool   InpTradeNewYork       = true;
input bool   InpTradePreLondon     = true;      // ENABLED: More opportunities
input bool   InpTradeAsian         = false;     // Keep disabled (low vol)

input int    InpSessionStartBuffer = 5;         // Reduced from 15
input int    InpSessionEndBuffer   = 5;         // Reduced from 15

// Quick Trade Management
input bool   InpUseQuickBreakeven  = true;
input int    InpBE_Trigger         = 60;        // 6 pips
input int    InpBE_Offset          = 5;

input bool   InpUseTrailingStop    = true;
input int    InpTrail_Start        = 100;       // 10 pips
input int    InpTrail_Distance     = 40;        // 4 pips trail

// Market Condition Filters (RELAXED)
input bool   InpAvoidHighVolatility = false;    // DISABLED: Was blocking trades
input double InpMaxATRPoints        = 800;
input bool   InpAvoidLowVolatility  = false;    // DISABLED
input double InpMinATRPoints        = 200;

// Time-of-Day Filter
input bool   InpAvoidFirstLastHour = false;     // DISABLED

// Display Settings
input group "=== DISPLAY SETTINGS ==="
input bool   InpEnableDebugLog     = true;
input bool   InpLogSignalAnalysis  = true;
input bool   InpShowDailyStats     = true;
input bool   InpShowAccountWarnings = true;
input bool   InpShowSessionStatus  = true;
input bool   InpShowTradeStatus    = true;
input int    InpStatusUpdateSeconds = 5;

//----------------------------
// Globals
//----------------------------
int    hFastEma   = INVALID_HANDLE;
int    hSlowEma   = INVALID_HANDLE;
int    hRsi       = INVALID_HANDLE;
int    hAtr       = INVALID_HANDLE;
int    hMomentum  = INVALID_HANDLE;
int    hADX       = INVALID_HANDLE;

datetime g_lastBarTime = 0;
datetime g_lastTradeTime = 0;
datetime g_lastStatusTime = 0;

int     g_tradesToday = 0;
int     g_winsToday = 0;
int     g_lossesToday = 0;
double  g_profitToday = 0.0;
int     g_todayDoy = -1;

// Session status globals
string  g_currentSession = "NONE";
string  g_sessionStatus = "WAITING";
color   g_sessionColor = clrGray;
bool    g_isTradeAllowed = false;
string  g_nextSession = "";
datetime g_nextSessionTime = 0;

// Signal tracking for debugging
int     g_signalChecks = 0;
int     g_lastSignalHour = -1;

//----------------------------
// Session Definitions
//----------------------------
enum ENUM_SESSION
{
   SESSION_ASIAN,      // 00:00 - 08:00 GMT
   SESSION_PRE_LONDON, // 07:00 - 08:00 GMT
   SESSION_LONDON,     // 08:00 - 12:00 GMT
   SESSION_LONDON_NY,  // 12:00 - 16:00 GMT (Overlap)
   SESSION_NEW_YORK,   // 13:00 - 21:00 GMT
   SESSION_CLOSED      // 21:00 - 00:00 GMT
};

//----------------------------
// Helpers
//----------------------------
void DebugLog(string msg)
{
   if(InpEnableDebugLog) Print("[$50-TUNED] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " | ", msg);
}

bool IsXAUUSD(const string sym)
{
   return (StringFind(sym, "XAUUSD") >= 0 || StringFind(sym, "GOLD") >= 0);
}

int CurrentDoy()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   MqlDateTime jan1 = tm;
   jan1.mon=1; jan1.day=1; jan1.hour=0; jan1.min=0; jan1.sec=0;
   datetime tJan1 = StructToTime(jan1);
   return (int)((TimeCurrent() - tJan1) / 86400);
}

void ShowAccountWarning()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   if(balance < 50.0 && InpShowAccountWarnings)
   {
      DebugLog("[WARN] Account balance ($" + DoubleToString(balance, 2) + ") is below $50.");
   }
   
   if(balance >= 50.0 && balance < 100.0 && InpShowAccountWarnings)
   {
      DebugLog("[OK] Account balance ($" + DoubleToString(balance, 2) + ") suitable for $50 strategy.");
      DebugLog("[INFO] Recommended: 0.02 lots per trade, max 0.03");
      DebugLog("[INFO] Daily limit: Stop at $5 loss or $10 profit");
   }
}

void ResetDailyCountersIfNeeded()
{
   int doy = CurrentDoy();
   if(doy != g_todayDoy)
   {
      if(g_todayDoy != -1 && InpShowDailyStats)
      {
         DebugLog("========== DAILY SUMMARY ==========");
         DebugLog("Total Trades: " + IntegerToString(g_tradesToday));
         DebugLog("Wins: " + IntegerToString(g_winsToday) + " | Losses: " + IntegerToString(g_lossesToday));
         if(g_tradesToday > 0)
         {
            double winRate = (double)g_winsToday / (double)g_tradesToday * 100.0;
            DebugLog("Win Rate: " + DoubleToString(winRate, 1) + "%");
         }
         DebugLog("Daily P&L: $" + DoubleToString(g_profitToday, 2));
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         DebugLog("Account Balance: $" + DoubleToString(balance, 2));
         DebugLog("===================================");
      }
      
      g_todayDoy = doy;
      g_tradesToday = 0;
      g_winsToday = 0;
      g_lossesToday = 0;
      g_profitToday = 0.0;
      g_signalChecks = 0;
      
      ShowAccountWarning();
   }
}

void UpdateDailyStats()
{
   ResetDailyCountersIfNeeded();
   
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00:00");
   
   g_winsToday = 0;
   g_lossesToday = 0;
   g_profitToday = 0.0;
   
   // Use a simple array to track processed position IDs (max 100 positions per day)
   ulong processedPositions[100];
   int processedCount = 0;
   
   HistorySelect(todayStart, TimeCurrent());
   int total = HistoryDealsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      
      // Only count OUT deals (closes)
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      
      // Get position ID for this deal
      ulong positionID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      
      // Add profit to daily total (all deals contribute to P&L)
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double netProfit = profit + commission + swap;
      g_profitToday += netProfit;
      
      // Check if we already counted this position
      bool alreadyCounted = false;
      for(int j = 0; j < processedCount; j++)
      {
         if(processedPositions[j] == positionID)
         {
            alreadyCounted = true;
            break;
         }
      }
      
      if(alreadyCounted) continue;
      
      // This is a new position - count it as win or loss
      // Need to calculate total profit for entire position
      double totalPositionProfit = 0;
      for(int k = 0; k < total; k++)
      {
         ulong checkTicket = HistoryDealGetTicket(k);
         if(checkTicket == 0) continue;
         if(HistoryDealGetInteger(checkTicket, DEAL_POSITION_ID) != positionID) continue;
         if(HistoryDealGetString(checkTicket, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(checkTicket, DEAL_MAGIC) != InpMagic) continue;
         
         totalPositionProfit += HistoryDealGetDouble(checkTicket, DEAL_PROFIT);
         totalPositionProfit += HistoryDealGetDouble(checkTicket, DEAL_COMMISSION);
         totalPositionProfit += HistoryDealGetDouble(checkTicket, DEAL_SWAP);
      }
      
      // Mark position as processed
      if(processedCount < 100)
      {
         processedPositions[processedCount] = positionID;
         processedCount++;
      }
      
      // Count as win or loss based on total position profit
      if(totalPositionProfit > 0.01) g_winsToday++;
      else if(totalPositionProfit < -0.01) g_lossesToday++;
   }
}

bool IsNewBar()
{
   MqlRates rates[2];
   if(CopyRates(_Symbol, InpTimeframe, 0, 2, rates) < 2) return false;
   if(rates[0].time != g_lastBarTime)
   {
      g_lastBarTime = rates[0].time;
      return true;
   }
   return false;
}

bool SpreadOK()
{
   int spreadPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (spreadPoints > 0 && spreadPoints <= InpMaxSpreadPoints);
}

//+------------------------------------------------------------------+
//| SESSION MANAGEMENT FUNCTIONS                                      |
//+------------------------------------------------------------------+

ENUM_SESSION GetCurrentSession(int &hour, int &min)
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   hour = tm.hour;
   min = tm.min;
   
   if(hour >= 0 && hour < 7)
      return SESSION_ASIAN;
   else if(hour >= 7 && hour < 8)
      return SESSION_PRE_LONDON;
   else if(hour >= 8 && hour < 12)
      return SESSION_LONDON;
   else if(hour >= 12 && hour < 16)
      return SESSION_LONDON_NY;
   else if(hour >= 16 && hour < 21)
      return SESSION_NEW_YORK;
   else
      return SESSION_CLOSED;
}

string GetSessionName(ENUM_SESSION session)
{
   switch(session)
   {
      case SESSION_ASIAN:      return "ASIAN";
      case SESSION_PRE_LONDON: return "PRE-LONDON";
      case SESSION_LONDON:     return "LONDON";
      case SESSION_LONDON_NY:  return "LONDON-NY OVERLAP";
      case SESSION_NEW_YORK:   return "NEW YORK";
      case SESSION_CLOSED:     return "CLOSED";
      default:                 return "UNKNOWN";
   }
}

color GetSessionColor(ENUM_SESSION session, bool isActive)
{
   if(!isActive) return clrGray;
   
   switch(session)
   {
      case SESSION_ASIAN:      return clrDarkOrange;
      case SESSION_PRE_LONDON: return clrYellow;
      case SESSION_LONDON:     return clrDodgerBlue;
      case SESSION_LONDON_NY:  return clrLime;
      case SESSION_NEW_YORK:   return clrMediumSeaGreen;
      case SESSION_CLOSED:     return clrGray;
      default:                 return clrWhite;
   }
}

bool IsSessionEnabled(ENUM_SESSION session)
{
   switch(session)
   {
      case SESSION_ASIAN:      return InpTradeAsian;
      case SESSION_PRE_LONDON: return InpTradePreLondon;
      case SESSION_LONDON:     return InpTradeLondon;
      case SESSION_LONDON_NY:  return InpTradeLondonNY;
      case SESSION_NEW_YORK:   return InpTradeNewYork;
      case SESSION_CLOSED:     return false;
      default:                 return false;
   }
}

bool IsInSessionBuffer(int hour, int min, ENUM_SESSION session)
{
   int startHour, endHour;
   
   switch(session)
   {
      case SESSION_ASIAN:      startHour=0;  endHour=8;  break;
      case SESSION_PRE_LONDON: startHour=7;  endHour=8;  break;
      case SESSION_LONDON:     startHour=8;  endHour=12; break;
      case SESSION_LONDON_NY:  startHour=12; endHour=16; break;
      case SESSION_NEW_YORK:   startHour=13; endHour=21; break;
      default: return false;
   }
   
   if(hour == startHour && min < InpSessionStartBuffer) return false;
   if(hour == (endHour-1) && min >= (60-InpSessionEndBuffer)) return false;
   
   return true;
}

void CalculateNextSession()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int currentHour = tm.hour;
   
   g_nextSession = "";
   g_nextSessionTime = 0;
   
   for(int h = currentHour + 1; h <= 24; h++)
   {
      int checkHour = (h > 23) ? h - 24 : h;
      ENUM_SESSION nextSess;
      
      if(checkHour >= 0 && checkHour < 7) nextSess = SESSION_ASIAN;
      else if(checkHour >= 7 && checkHour < 8) nextSess = SESSION_PRE_LONDON;
      else if(checkHour >= 8 && checkHour < 12) nextSess = SESSION_LONDON;
      else if(checkHour >= 12 && checkHour < 16) nextSess = SESSION_LONDON_NY;
      else if(checkHour >= 16 && checkHour < 21) nextSess = SESSION_NEW_YORK;
      else nextSess = SESSION_CLOSED;
      
      if(IsSessionEnabled(nextSess) && nextSess != SESSION_CLOSED)
      {
         MqlDateTime nextTm = tm;
         if(h > 23) 
         {
            datetime nextDay = TimeCurrent() + 86400;
            TimeToStruct(nextDay, nextTm);
         }
         
         if(nextSess == SESSION_ASIAN) nextTm.hour = 0;
         else if(nextSess == SESSION_PRE_LONDON) nextTm.hour = 7;
         else if(nextSess == SESSION_LONDON) nextTm.hour = 8;
         else if(nextSess == SESSION_LONDON_NY) nextTm.hour = 12;
         else if(nextSess == SESSION_NEW_YORK) nextTm.hour = 13;
         
         nextTm.min = InpSessionStartBuffer;
         nextTm.sec = 0;
         
         g_nextSession = GetSessionName(nextSess);
         g_nextSessionTime = StructToTime(nextTm);
         return;
      }
   }
}

void UpdateSessionStatus()
{
   if(!InpShowSessionStatus) return;
   
   int hour, min;
   ENUM_SESSION session = GetCurrentSession(hour, min);
   string sessionName = GetSessionName(session);
   
   bool enabled = IsSessionEnabled(session);
   bool inBuffer = IsInSessionBuffer(hour, min, session);
   bool spreadOk = SpreadOK();
   
   g_isTradeAllowed = false;
   g_sessionStatus = "BLOCKED";
   
   if(!InpUseSessionFilter)
   {
      g_isTradeAllowed = true;
      g_sessionStatus = "ACTIVE (No Filter)";
   }
   else if(!enabled)
   {
      g_sessionStatus = "DISABLED";
   }
   else if(!inBuffer)
   {
      if(hour == 7 || (hour == 8 && min < InpSessionStartBuffer))
         g_sessionStatus = "WAITING (Start Buffer)";
      else
         g_sessionStatus = "COOLING (End Buffer)";
   }
   else if(!spreadOk)
   {
      g_sessionStatus = "HIGH SPREAD";
   }
   else
   {
      g_isTradeAllowed = true;
      g_sessionStatus = "[ACTIVE] TRADING ENABLED";
   }
   
   g_currentSession = sessionName;
   g_sessionColor = GetSessionColor(session, enabled && inBuffer);
   
   if(!g_isTradeAllowed)
   {
      CalculateNextSession();
   }
}

void DisplayStatus()
{
   if(!InpShowSessionStatus && !InpShowTradeStatus) return;
   
   datetime now = TimeCurrent();
   if(now - g_lastStatusTime < InpStatusUpdateSeconds) return;
   g_lastStatusTime = now;
   
   UpdateSessionStatus();
   
   string status = "";
   
   // Header
   status += "========================================\n";
   status += "     $50 SCALPER v5.00 - TUNED         \n";
   status += "     RELAXED SIGNALS EDITION           \n";
   status += "========================================\n";
   
   // Session Status
   string sessionLine = "SESSION: " + g_currentSession;
   status += sessionLine + "\n";
   
   string statusLine = "STATUS:  " + g_sessionStatus;
   status += statusLine + "\n";
   
   // Trade Allowed Indicator
   string tradeLine = "TRADING: " + (g_isTradeAllowed ? "[ON] ENABLED" : "[OFF] DISABLED");
   if(!g_isTradeAllowed && g_nextSession != "")
   {
      int minsToNext = (int)((g_nextSessionTime - now) / 60);
      if(minsToNext < 60)
         tradeLine += " (Next: " + g_nextSession + " in " + IntegerToString(minsToNext) + "m)";
      else
         tradeLine += " (Next: " + g_nextSession + ")";
   }
   status += tradeLine + "\n";
   status += "----------------------------------------\n";
   
   // Market Info
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   string priceLine = "PRICE: " + DoubleToString(bid, 2) + " | SPREAD: " + IntegerToString(spread) + " pts";
   if(spread > InpMaxSpreadPoints) priceLine += " [HIGH]";
   status += priceLine + "\n";
   
   // Account Info
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   string accLine = "BALANCE: $" + DoubleToString(balance, 2) + " | EQUITY: $" + DoubleToString(equity, 2);
   status += accLine + "\n";
   
   // Daily Stats
   UpdateDailyStats();
   string statsLine = "TODAY: " + IntegerToString(g_winsToday) + "W/" + 
                     IntegerToString(g_lossesToday) + "L | P&L: $" + DoubleToString(g_profitToday, 2);
   if(InpMaxDailyProfit > 0)
      statsLine += " | Limit: " + IntegerToString(g_winsToday) + "/" + IntegerToString(InpMaxDailyProfit);
   status += statsLine + "\n";
   
   // Signal Debug Info
   status += "----------------------------------------\n";
   string signalLine = "SIGNAL CHECKS TODAY: " + IntegerToString(g_signalChecks);
   status += signalLine + "\n";
   
   status += "----------------------------------------\n";
   
   // Position Status
   bool hasPos = HasOpenPosition();
   if(hasPos)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
         
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         double lots = PositionGetDouble(POSITION_VOLUME);
         double profit = PositionGetDouble(POSITION_PROFIT);
         
         double current = (type == POSITION_TYPE_BUY) ? bid : ask;
         double profitPts = (type == POSITION_TYPE_BUY) ? (current - entry)/_Point : (entry - current)/_Point;
         
         string posType = (type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         string posLine = "POSITION: #" + IntegerToString((int)ticket) + " " + posType + " " + 
                         DoubleToString(lots, 2) + " lots";
         status += posLine + "\n";
         
         string pnlLine = "P&L: $" + DoubleToString(profit, 2) + " | Points: " + DoubleToString(profitPts, 0);
         if(profitPts >= InpBE_Trigger) pnlLine += " [BE READY]";
         if(profitPts >= InpTrail_Start) pnlLine += " [TRAILING]";
         status += pnlLine + "\n";
      }
   }
   else
   {
      string noPosLine = "POSITION: No active trades";
      status += noPosLine + "\n";
   }
   
   status += "========================================";
   
   Comment(status);
}

bool TradingHoursOK()
{
   if(!InpUseSessionFilter) return true;
   
   int hour, min;
   ENUM_SESSION session = GetCurrentSession(hour, min);
   
   if(!IsSessionEnabled(session)) return false;
   if(!IsInSessionBuffer(hour, min, session)) return false;
   
   return true;
}

bool CooldownOK()
{
   if(InpCooldownSeconds <= 0) return true;
   return (TimeCurrent() - g_lastTradeTime) >= InpCooldownSeconds;
}

bool DailyLimitsOK()
{
   ResetDailyCountersIfNeeded();
   UpdateDailyStats();
   
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
   {
      DebugLog("[LIMIT] Daily trade limit reached (" + IntegerToString(g_tradesToday) + "/" + 
         IntegerToString(InpMaxTradesPerDay) + ")");
      return false;
   }
   
   if(InpMaxDailyLoss > 0 && g_lossesToday >= InpMaxDailyLoss)
   {
      DebugLog("[STOP] Daily loss limit reached (" + IntegerToString(g_lossesToday) + " losses)");
      return false;
   }
   
   if(InpMaxDailyLossDollars > 0 && g_profitToday <= -InpMaxDailyLossDollars)
   {
      DebugLog("[STOP] Daily loss limit reached ($" + DoubleToString(-g_profitToday, 2) + ")");
      return false;
   }
   
   if(InpMaxDailyProfit > 0 && g_winsToday >= InpMaxDailyProfit)
   {
      DebugLog("[TARGET] Daily profit target reached (" + IntegerToString(g_winsToday) + " wins)");
      return false;
   }
   
   if(InpMaxDailyProfitDollars > 0 && g_profitToday >= InpMaxDailyProfitDollars)
   {
      DebugLog("[TARGET] Daily profit target reached ($" + DoubleToString(g_profitToday, 2) + ")");
      return false;
   }
   
   return true;
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      return true;
   }
   return false;
}

double NormalizeVolume(double lots)
{
   double vMin=0, vMax=0, vStep=0;
   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, vMin);
   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, vMax);
   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, vStep);

   lots = MathMax(lots, vMin);
   lots = MathMin(lots, vMax);
   lots = MathMax(lots, InpMinLot);
   lots = MathMin(lots, InpMaxLot);

   if(vStep > 0)
      lots = MathFloor(lots / vStep) * vStep;

   return lots;
}

bool GetIndicatorValues(double &fastEma, double &slowEma, double &rsi, double &atr, double &momentum, double &adx)
{
   double bFast[3], bSlow[3], bRsi[3], bAtr[3], bMom[3], bAdx[3];

   if(CopyBuffer(hFastEma, 0, 0, 3, bFast) < 3) return false;
   if(CopyBuffer(hSlowEma, 0, 0, 3, bSlow) < 3) return false;
   if(CopyBuffer(hRsi, 0, 0, 3, bRsi) < 3) return false;
   if(CopyBuffer(hAtr, 0, 0, 3, bAtr) < 3) return false;
   
   if(hMomentum != INVALID_HANDLE)
   {
      if(CopyBuffer(hMomentum, 0, 0, 3, bMom) < 3) return false;
      momentum = bMom[1];
   }
   else momentum = 0;
   
   if(hADX != INVALID_HANDLE)
   {
      if(CopyBuffer(hADX, 0, 0, 3, bAdx) < 3) return false;
      adx = bAdx[1];
   }
   else adx = 0;

   fastEma = bFast[1];
   slowEma = bSlow[1];
   rsi = bRsi[1];
   atr = bAtr[1];

   return true;
}

bool CheckCandlePattern(bool isBuy)
{
   if(!InpRequirePriceAction) return true;
   
   MqlRates rates[3];
   if(CopyRates(_Symbol, InpTimeframe, 1, 3, rates) < 3) return true;
   
   double open = rates[0].open;
   double close = rates[0].close;
   double high = rates[0].high;
   double low = rates[0].low;
   
   double range = high - low;
   if(range <= 0) return false;
   
   double body = MathAbs(close - open);
   double bodyPercent = (body / range) * 100.0;
   
   if(bodyPercent < InpMinCandleBodyPercent)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] Candle too weak: " + DoubleToString(bodyPercent, 1) + "% body");
      return false;
   }
   
   if(isBuy && close <= open)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] BUY but bearish candle");
      return false;
   }
   
   if(!isBuy && close >= open)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] SELL but bullish candle");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| RELAXED BUY SIGNAL CHECK                                         |
//+------------------------------------------------------------------+
bool CheckBuySignal()
{
   double fe, se, rs, at, mom, adx;
   if(!GetIndicatorValues(fe, se, rs, at, mom, adx)) 
   {
      if(InpLogSignalAnalysis) DebugLog("[ERROR] BUY: Failed to get indicator values");
      return false;
   }

   double fast[5], slow[5];
   if(CopyBuffer(hFastEma, 0, 0, 5, fast) < 5) return false;
   if(CopyBuffer(hSlowEma, 0, 0, 5, slow) < 5) return false;

   // Track signal check
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   if(tm.hour != g_lastSignalHour)
   {
      g_lastSignalHour = tm.hour;
      g_signalChecks = 0;
   }
   g_signalChecks++;

   // ATR Volatility Check (Optional - RELAXED)
   double atrPts = at / _Point;
   if(InpAvoidHighVolatility && atrPts > InpMaxATRPoints)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] BUY: High volatility (ATR=" + DoubleToString(atrPts, 0) + ")");
      return false;
   }
   if(InpAvoidLowVolatility && atrPts < InpMinATRPoints)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] BUY: Low volatility (ATR=" + DoubleToString(atrPts, 0) + ")");
      return false;
   }

   // ADX Trend Strength (OPTIONAL - RELAXED)
   if(InpAvoidChoppyMarket && adx < InpMinADX)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] BUY: Weak trend (ADX=" + DoubleToString(adx, 1) + " < " + DoubleToString(InpMinADX, 1) + ")");
      return false;
   }

   // EMA Trend Alignment (RELAXED - can use cross OR alignment)
   bool emaBullish = fast[1] > slow[1];
   bool emaCrossUp = (fast[2] <= slow[2]) && (fast[1] > slow[1]);
   
   if(InpRequireTrendAlignment && !emaBullish)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] BUY: No trend (Fast <= Slow)");
      return false;
   }

   // EMA Distance Check (OPTIONAL)
   if(InpRequireEMADistance)
   {
      double emaDistance = (fast[1] - slow[1]) / _Point;
      if(emaDistance < InpMinEMADistancePoints)
      {
         if(InpLogSignalAnalysis)
            DebugLog("[FILTER] BUY: EMAs too close (" + DoubleToString(emaDistance, 1) + " pts)");
         return false;
      }
   }

   // Momentum (OPTIONAL - RELAXED)
   if(InpRequireStrongMomentum && mom < InpMinMomentumThreshold)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] BUY: Weak momentum (" + DoubleToString(mom, 5) + ")");
      return false;
   }

   // RSI Confirmation (WIDENED ZONES)
   if(InpRequireRSIConfirmation)
   {
      if(rs < InpRSI_BuyMin || rs > InpRSI_BuyMax)
      {
         if(InpLogSignalAnalysis)
            DebugLog("[FILTER] BUY: RSI out of zone (" + DoubleToString(rs, 1) + " not in " + 
               DoubleToString(InpRSI_BuyMin, 0) + "-" + DoubleToString(InpRSI_BuyMax, 0) + ")");
         return false;
      }
   }

   // Candle Pattern (OPTIONAL)
   if(!CheckCandlePattern(true)) return false;

   // === RELAXED ENTRY PATTERNS ===
   bool entrySignal = false;
   string patternName = "";
   
   // Pattern 1: EMA Cross
   if(InpUseEMACrossEntry && emaCrossUp)
   {
      entrySignal = true;
      patternName = "EMA-CROSS-UP";
   }
   // Pattern 2: RSI Bounce from oversold
   else if(InpUseRSIBounceEntry && rs > InpRSI_BuyMin && rs < 55 && emaBullish)
   {
      entrySignal = true;
      patternName = "RSI-BOUNCE-UP";
   }
   // Pattern 3: Trend Following
   else if(InpUseTrendFollowEntry && emaBullish && fast[1] > fast[2] && slow[1] > slow[2])
   {
      entrySignal = true;
      patternName = "TREND-FOLLOW-UP";
   }
   // Pattern 4: Price above both EMAs with RSI support
   else if(fast[1] > slow[1] && rs >= 45 && rs <= 65)
   {
      entrySignal = true;
      patternName = "EMA-SUPPORT-UP";
   }
   
   if(!entrySignal)
   {
      if(InpLogSignalAnalysis && (g_signalChecks % 10 == 0)) // Log every 10th check to avoid spam
      {
         DebugLog("[FILTER] BUY: No entry pattern | RSI=" + DoubleToString(rs, 1) + 
            " EMA=" + (emaBullish ? "BULL" : "BEAR") + " Cross=" + (emaCrossUp ? "YES" : "NO"));
      }
      return false;
   }

   if(InpLogSignalAnalysis)
   {
      DebugLog("[SIGNAL] BUY SIGNAL: " + patternName + " | RSI=" + DoubleToString(rs, 1) + 
         " | ADX=" + DoubleToString(adx, 1) + " | ATR=" + DoubleToString(atrPts, 0));
   }

   return true;
}

//+------------------------------------------------------------------+
//| RELAXED SELL SIGNAL CHECK                                        |
//+------------------------------------------------------------------+
bool CheckSellSignal()
{
   double fe, se, rs, at, mom, adx;
   if(!GetIndicatorValues(fe, se, rs, at, mom, adx)) 
   {
      if(InpLogSignalAnalysis) DebugLog("[FILTER] SELL: Failed to get indicator values");
      return false;
   }

   double fast[5], slow[5];
   if(CopyBuffer(hFastEma, 0, 0, 5, fast) < 5) return false;
   if(CopyBuffer(hSlowEma, 0, 0, 5, slow) < 5) return false;

   // Track signal check
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   if(tm.hour != g_lastSignalHour)
   {
      g_lastSignalHour = tm.hour;
      g_signalChecks = 0;
   }
   g_signalChecks++;

   double atrPts = at / _Point;
   if(InpAvoidHighVolatility && atrPts > InpMaxATRPoints)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] SELL: High volatility");
      return false;
   }
   if(InpAvoidLowVolatility && atrPts < InpMinATRPoints)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] SELL: Low volatility");
      return false;
   }

   if(InpAvoidChoppyMarket && adx < InpMinADX)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] SELL: Weak trend (ADX=" + DoubleToString(adx, 1) + ")");
      return false;
   }

   // EMA Trend Alignment (RELAXED)
   bool emaBearish = fast[1] < slow[1];
   bool emaCrossDown = (fast[2] >= slow[2]) && (fast[1] < slow[1]);
   
   if(InpRequireTrendAlignment && !emaBearish)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] SELL: No trend (Fast >= Slow)");
      return false;
   }

   if(InpRequireEMADistance)
   {
      double emaDistance = (slow[1] - fast[1]) / _Point;
      if(emaDistance < InpMinEMADistancePoints)
      {
         if(InpLogSignalAnalysis)
            DebugLog("[FILTER] SELL: EMAs too close (" + DoubleToString(emaDistance, 1) + " pts)");
         return false;
      }
   }

   if(InpRequireStrongMomentum && mom > -InpMinMomentumThreshold)
   {
      if(InpLogSignalAnalysis)
         DebugLog("[FILTER] SELL: Weak momentum");
      return false;
   }

   // RSI Confirmation (WIDENED ZONES)
   if(InpRequireRSIConfirmation)
   {
      if(rs < InpRSI_SellMin || rs > InpRSI_SellMax)
      {
         if(InpLogSignalAnalysis)
            DebugLog("[FILTER] SELL: RSI out of zone (" + DoubleToString(rs, 1) + " not in " + 
               DoubleToString(InpRSI_SellMin, 0) + "-" + DoubleToString(InpRSI_SellMax, 0) + ")");
         return false;
      }
   }

   if(!CheckCandlePattern(false)) return false;

   // === RELAXED ENTRY PATTERNS ===
   bool entrySignal = false;
   string patternName = "";
   
   // Pattern 1: EMA Cross
   if(InpUseEMACrossEntry && emaCrossDown)
   {
      entrySignal = true;
      patternName = "EMA-CROSS-DOWN";
   }
   // Pattern 2: RSI Bounce from overbought
   else if(InpUseRSIBounceEntry && rs < InpRSI_SellMax && rs > 45 && emaBearish)
   {
      entrySignal = true;
      patternName = "RSI-BOUNCE-DOWN";
   }
   // Pattern 3: Trend Following
   else if(InpUseTrendFollowEntry && emaBearish && fast[1] < fast[2] && slow[1] < slow[2])
   {
      entrySignal = true;
      patternName = "TREND-FOLLOW-DOWN";
   }
   // Pattern 4: Price below both EMAs with RSI resistance
   else if(fast[1] < slow[1] && rs >= 35 && rs <= 55)
   {
      entrySignal = true;
      patternName = "EMA-RESIST-DOWN";
   }
   
   if(!entrySignal)
   {
      if(InpLogSignalAnalysis && (g_signalChecks % 10 == 0))
      {
         DebugLog("[FILTER] SELL: No entry pattern | RSI=" + DoubleToString(rs, 1) + 
            " EMA=" + (emaBearish ? "BEAR" : "BULL") + " Cross=" + (emaCrossDown ? "YES" : "NO"));
      }
      return false;
   }

   if(InpLogSignalAnalysis)
   {
      DebugLog("[SIGNAL] SELL SIGNAL: " + patternName + " | RSI=" + DoubleToString(rs, 1) + 
         " | ADX=" + DoubleToString(adx, 1) + " | ATR=" + DoubleToString(atrPts, 0));
   }

   return true;
}

bool OpenTrade(bool isBuy)
{
   double lots = NormalizeVolume(InpFixedLot);
   if(lots <= 0)
   {
      DebugLog("Invalid lot size");
      return false;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = isBuy ? ask : bid;

   int slPts = InpScalpSL_Points;
   int tpPts = InpScalpTP_Points;

   double sl=0, tp=0;
   if(isBuy)
   {
      sl = entry - slPts * _Point;
      tp = entry + tpPts * _Point;
   }
   else
   {
      sl = entry + slPts * _Point;
      tp = entry - tpPts * _Point;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviationPoints);

   string side = isBuy ? "BUY" : "SELL";
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   DebugLog("[OPEN] OPENING " + side + " | Lot=" + DoubleToString(lots, 2) + 
      " Entry=" + DoubleToString(entry, _Digits) + 
      " SL=" + IntegerToString(slPts) + "pts TP=" + IntegerToString(tpPts) + "pts Spread=" + IntegerToString(spread));

   bool ok = false;
   if(isBuy) ok = trade.Buy(lots, _Symbol, entry, sl, tp, "$50-TUNED BUY");
   else      ok = trade.Sell(lots, _Symbol, entry, sl, tp, "$50-TUNED SELL");

   if(ok)
   {
      g_lastTradeTime = TimeCurrent();
      ResetDailyCountersIfNeeded();
      g_tradesToday++;
      
      DebugLog("[OK] TRADE OPENED " + side + " #" + IntegerToString(trade.ResultOrder()));
      DebugLog("  Today: " + IntegerToString(g_tradesToday) + " trades | " + 
         IntegerToString(g_winsToday) + "W/" + IntegerToString(g_lossesToday) + "L | " +
         "P&L: $" + DoubleToString(g_profitToday, 2) + " | Balance: $" + DoubleToString(balance, 2));
   }
   else
   {
      DebugLog("[FILTER] FAILED " + side + " | Error: " + IntegerToString(trade.ResultRetcode()) + 
         " - " + trade.ResultRetcodeDescription());
   }
   
   return ok;
}

void ManagePosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double lots = PositionGetDouble(POSITION_VOLUME);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price = (type == POSITION_TYPE_BUY) ? bid : ask;

      double profitPts = 0;
      if(type == POSITION_TYPE_BUY) profitPts = (price - entry) / _Point;
      if(type == POSITION_TYPE_SELL) profitPts = (entry - price) / _Point;

      // Partial Take Profit
      if(InpUsePartialTP && profitPts >= InpPartialTP_Points)
      {
         string comment = PositionGetString(POSITION_COMMENT);
         if(StringFind(comment, "PARTIAL") < 0)
         {
            double closeVol = NormalizeVolume(lots * InpPartialClosePercent / 100.0);
            if(closeVol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
               trade.SetExpertMagicNumber(InpMagic);
               if(trade.PositionClosePartial(ticket, closeVol))
               {
                  DebugLog("  [OK] Partial close " + DoubleToString(closeVol, 2) + " lots at +" + 
                     DoubleToString(profitPts, 0) + " pts (locking profit)");
               }
            }
         }
      }

      double newSL = sl;

      // Quick Breakeven
      if(InpUseQuickBreakeven && profitPts >= InpBE_Trigger)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double be = entry + InpBE_Offset * _Point;
            if(sl < be || sl == 0.0) newSL = be;
         }
         else
         {
            double be = entry - InpBE_Offset * _Point;
            if(sl > be || sl == 0.0) newSL = be;
         }
      }

      // Trailing Stop
      if(InpUseTrailingStop && profitPts >= InpTrail_Start)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double trailSL = price - InpTrail_Distance * _Point;
            if(trailSL > newSL) newSL = trailSL;
         }
         else
         {
            double trailSL = price + InpTrail_Distance * _Point;
            if(trailSL < newSL || newSL == 0.0) newSL = trailSL;
         }
      }

      if(newSL != sl && MathAbs(newSL - sl) > _Point * 3)
      {
         trade.SetExpertMagicNumber(InpMagic);
         if(trade.PositionModify(ticket, newSL, tp))
         {
            DebugLog("  [OK] SL adjusted to " + DoubleToString(newSL, _Digits) + 
               " (profit: +" + DoubleToString(profitPts, 0) + " pts)");
         }
      }
   }
}

//----------------------------
// Event Handlers
//----------------------------
int OnInit()
{
   if(!IsXAUUSD(_Symbol))
   {
      Print("This EA is for XAUUSD/GOLD only. Symbol: ", _Symbol);
      return(INIT_FAILED);
   }

   hFastEma = iMA(_Symbol, InpTimeframe, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEma = iMA(_Symbol, InpTimeframe, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRsi = iRSI(_Symbol, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   hAtr = iATR(_Symbol, InpTimeframe, InpATRPeriod);
   hMomentum = iMomentum(_Symbol, InpTimeframe, InpMomentumPeriod, PRICE_CLOSE);
   hADX = iADX(_Symbol, InpTimeframe, InpADXPeriod);

   if(hFastEma == INVALID_HANDLE || hSlowEma == INVALID_HANDLE ||
      hRsi == INVALID_HANDLE || hAtr == INVALID_HANDLE)
   {
      Print("Failed to create essential indicators");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InpMagic);

   g_lastBarTime = 0;
   g_lastTradeTime = 0;
   g_lastStatusTime = 0;
   g_todayDoy = CurrentDoy();
   g_tradesToday = 0;
   g_winsToday = 0;
   g_lossesToday = 0;
   g_signalChecks = 0;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("========================================");
   Print("   $50 SCALPER v5.00 - TUNED EDITION   ");
   Print("   RELAXED SIGNALS - MORE OPPORTUNITIES");
   Print("========================================");
   Print("Account Balance: $", DoubleToString(balance, 2));
   Print("Strategy: Relaxed Filters (More Trades)");
   Print("Lot Size: ", InpFixedLot, " (Max: ", InpMaxLot, ")");
   Print("Risk/Trade: ~$", DoubleToString(InpScalpSL_Points * 0.01, 2), " | Profit/Trade: ~$", DoubleToString(InpScalpTP_Points * 0.01, 2));
   Print("Daily Limits: Max ", InpMaxDailyLoss, " losses OR $", InpMaxDailyProfitDollars, " profit");
   Print("SL: ", InpScalpSL_Points, " pts | TP: ", InpScalpTP_Points, " pts");
   Print("Spread Limit: ", InpMaxSpreadPoints, " pts (RELAXED)");
   Print("========================================");
   Print("RELAXED FILTERS:");
   Print("   [OK] RSI Zone: 40-70 (buy) / 30-60 (sell) - WIDENED");
   Print("   [OK] Momentum Filter: DISABLED");
   Print("   [OK] ADX Filter: DISABLED");
   Print("   [OK] EMA Distance: DISABLED");
   Print("   [OK] Candle Body: OPTIONAL");
   Print("========================================");
   Print("SESSION SCHEDULE:");
   Print("   Pre-London:        07:00-08:00 GMT [ENABLED]");
   Print("   London Session:    08:00-12:00 GMT [ENABLED]");
   Print("   London-NY Overlap: 12:00-16:00 GMT [PEAK SCALPING]");
   Print("   New York Session:  13:00-21:00 GMT [ENABLED]");
   Print("========================================");
   
   ShowAccountWarning();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(hFastEma != INVALID_HANDLE) IndicatorRelease(hFastEma);
   if(hSlowEma != INVALID_HANDLE) IndicatorRelease(hSlowEma);
   if(hRsi != INVALID_HANDLE) IndicatorRelease(hRsi);
   if(hAtr != INVALID_HANDLE) IndicatorRelease(hAtr);
   if(hMomentum != INVALID_HANDLE) IndicatorRelease(hMomentum);
   if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);

   UpdateDailyStats();
   Comment("");
   
   Print("$50 Scalper deinitialized");
   Print("Final Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
}

void OnTick()
{
   if(!IsXAUUSD(_Symbol)) return;

   DisplayStatus();

   ManagePosition();

   if(!IsNewBar()) return;

   int spreadPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(!SpreadOK())
   {
      if(InpLogSignalAnalysis && (g_signalChecks % 20 == 0))
         DebugLog("[FILTER] SKIP: Spread too high (" + IntegerToString(spreadPts) + " > " + 
            IntegerToString(InpMaxSpreadPoints) + ")");
      return;
   }

   if(!TradingHoursOK())
   {
      return;
   }

   if(!CooldownOK())
   {
      int remaining = InpCooldownSeconds - (int)(TimeCurrent() - g_lastTradeTime);
      if(remaining > 0 && (g_signalChecks % 10 == 0))
         DebugLog("[WAIT] Cooldown: " + IntegerToString(remaining) + "s remaining");
      return;
   }

   if(!DailyLimitsOK())
   {
      return;
   }

   if(InpOnePositionOnly && HasOpenPosition())
   {
      return;
   }

   bool buySignal = CheckBuySignal();
   bool sellSignal = CheckSellSignal();

   if(buySignal && sellSignal)
   {
      DebugLog("[FILTER] Conflicting signals - skipping");
      return;
   }

   if(buySignal) OpenTrade(true);
   if(sellSignal) OpenTrade(false);
}
//+------------------------------------------------------------------+
