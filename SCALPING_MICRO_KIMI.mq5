//+------------------------------------------------------------------+
//|                                         SCALPING_MICROACCOUNT.mq5 |
//|                    Ultra-Micro Account Scalper for $10-$20       |
//+------------------------------------------------------------------+
#property strict
#property version   "4.00"
#property description "XAUUSD Micro-Account Scalper: Optimized for $10-$20 accounts"
#property description "Ultra-tight stops, micro lots, maximum win rate focus"
#property description "Enhanced Session Management with Real-time Status Display"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo pos;

//----------------------------
// Inputs - MICRO ACCOUNT OPTIMIZED
//----------------------------
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M5;
input long            InpMagic            = 20260211;
input bool            InpOnePositionOnly  = true;

// Risk Management (ULTRA CONSERVATIVE)
input double InpFixedLot           = 0.01;    // 0.01 = MINIMUM (broker must support)
input double InpMaxLot             = 0.01;    // NEVER increase (safety)
input double InpMinLot             = 0.01;

// Daily Protection (CRITICAL for micro accounts)
input int    InpMaxDailyLoss       = 2;       // Stop after 2 losses (~$1-2 loss max)
input int    InpMaxDailyProfit     = 5;       // Stop after 5 wins (~$2.50-5 profit)
input double InpMaxDailyLossDollars = 2.0;    // Hard stop at $2 loss
input double InpMaxDailyProfitDollars = 5.0;  // Take profit at $5 gain

// Scalping Stops/Targets (VERY TIGHT)
input int    InpScalpSL_Points     = 100;     // 10 pips (~$1.00 risk)
input int    InpScalpTP_Points     = 150;     // 15 pips (~$1.50 profit)
input bool   InpUsePartialTP       = true;    // Lock profit fast
input int    InpPartialTP_Points   = 80;      // Close 60% at 8 pips
input double InpPartialClosePercent = 60.0;   // Close 60% early

// Spread Filter (EXTREMELY STRICT)
input int    InpMaxSpreadPoints    = 50;      // Only ultra-tight spreads
input int    InpDeviationPoints    = 10;

// Entry Filters (ULTRA CONSERVATIVE - Maximum Win Rate)
input int    InpFastEMA            = 9;
input int    InpSlowEMA            = 21;
input int    InpRSIPeriod          = 14;
input int    InpATRPeriod          = 14;

// Win Rate Maximization (ALL FILTERS REQUIRED)
input bool   InpRequireStrongMomentum = true;
input int    InpMomentumPeriod        = 10;
input double InpMinMomentumThreshold  = 0.0005;  // Very strong only

input bool   InpRequireTrendAlignment = true;
input bool   InpAvoidChoppyMarket     = true;
input int    InpADXPeriod             = 14;
input double InpMinADX                = 25.0;    // Strong trends only

input bool   InpRequireRSIConfirmation = true;
input double InpRSI_BuyMin            = 50.0;    // Very narrow zones
input double InpRSI_BuyMax            = 60.0;
input double InpRSI_SellMin           = 40.0;
input double InpRSI_SellMax           = 50.0;

input bool   InpRequirePriceAction    = true;
input double InpMinCandleBodyPercent  = 50.0;    // Strong candles only

input bool   InpRequireEMADistance    = true;    // NEW: EMA must be separated
input double InpMinEMADistancePoints  = 20.0;    // Min distance between EMAs

// Overtrading Protection (STRICT)
input int    InpCooldownSeconds    = 600;       // 10 min cooldown
input int    InpMaxTradesPerDay    = 8;         // Very selective

// SESSION MANAGEMENT - ENHANCED
input group "=== SESSION MANAGEMENT ==="
input bool   InpUseSessionFilter   = true;
input bool   InpTradeLondon        = true;      // 08:00-12:00 GMT (Trend setup)
input bool   InpTradeLondonNY      = true;      // 12:00-16:00 GMT (PEAK SCALPING)
input bool   InpTradeNewYork       = true;      // 13:00-21:00 GMT (US session)
input bool   InpTradePreLondon     = false;     // 07:00-08:00 GMT (Early setup)
input bool   InpTradeAsian         = false;     // 00:00-08:00 GMT (Avoid - low vol)

input int    InpSessionStartBuffer = 15;        // Skip first N minutes of session
input int    InpSessionEndBuffer   = 15;        // Skip last N minutes of session

// Quick Trade Management
input bool   InpUseQuickBreakeven  = true;
input int    InpBE_Trigger         = 50;        // Move to BE at 5 pips
input int    InpBE_Offset          = 5;         // +0.5 pip lock

input bool   InpUseTrailingStop    = true;
input int    InpTrail_Start        = 80;        // Start at 8 pips
input int    InpTrail_Distance     = 30;        // Trail 3 pips behind

// Market Condition Filters (STRICT)
input bool   InpAvoidHighVolatility = true;
input double InpMaxATRPoints        = 600;      // Avoid high volatility
input bool   InpAvoidLowVolatility  = true;
input double InpMinATRPoints        = 300;      // Avoid low volatility

// Time-of-Day Filter (NEW)
input bool   InpAvoidFirstLastHour = true;      // Skip first/last hour of session

// Display Settings
input group "=== DISPLAY SETTINGS ==="
input bool   InpEnableDebugLog     = true;
input bool   InpLogSignalAnalysis  = true;
input bool   InpShowDailyStats     = true;
input bool   InpShowAccountWarnings = true;     // Warn if account < $20
input bool   InpShowSessionStatus  = true;      // Show current session status
input bool   InpShowTradeStatus    = true;      // Show trade monitoring status
input int    InpStatusUpdateSeconds = 5;        // Update frequency for status

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
   if(InpEnableDebugLog) Print("[MICRO-$10] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " | ", msg);
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
   
   if(balance < 20.0 && InpShowAccountWarnings)
   {
      DebugLog("⚠️ WARNING: Account balance ($" + DoubleToString(balance, 2) + 
         ") is below $20. Risk management is CRITICAL!");
      DebugLog("⚠️ Use 0.01 lot ONLY. Max loss per trade: $1.00");
      DebugLog("⚠️ Daily limit: Stop after 2 losses or 5 wins");
   }
   
   if(balance < 10.0 && InpShowAccountWarnings)
   {
      DebugLog("🚨 CRITICAL: Account below $10! Extreme caution required.");
      DebugLog("🚨 Consider depositing more funds for safer trading.");
   }
}

void ResetDailyCountersIfNeeded()
{
   int doy = CurrentDoy();
   if(doy != g_todayDoy)
   {
      if(g_todayDoy != -1 && InpShowDailyStats)
      {
         DebugLog("╔════════════ DAILY SUMMARY ════════════╗");
         DebugLog("║ Total Trades: " + IntegerToString(g_tradesToday));
         DebugLog("║ Wins: " + IntegerToString(g_winsToday) + " | Losses: " + IntegerToString(g_lossesToday));
         if(g_tradesToday > 0)
         {
            double winRate = (double)g_winsToday / (double)g_tradesToday * 100.0;
            DebugLog("║ Win Rate: " + DoubleToString(winRate, 1) + "%");
         }
         DebugLog("║ Daily P&L: $" + DoubleToString(g_profitToday, 2));
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         DebugLog("║ Account Balance: $" + DoubleToString(balance, 2));
         DebugLog("╚═══════════════════════════════════════╝");
      }
      
      g_todayDoy = doy;
      g_tradesToday = 0;
      g_winsToday = 0;
      g_lossesToday = 0;
      g_profitToday = 0.0;
      
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
   
   HistorySelect(todayStart, TimeCurrent());
   int total = HistoryDealsTotal();
   
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      
      double netProfit = profit + commission + swap;
      g_profitToday += netProfit;
      
      if(netProfit > 0.01) g_winsToday++;
      else if(netProfit < -0.01) g_lossesToday++;
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
   
   // Convert to GMT (assuming broker time is GMT+2/3, adjust as needed)
   // Most brokers use GMT+2 (winter) or GMT+3 (summer)
   // For accuracy, we use the hour from server time and assume GMT offset handling
   
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
      case SESSION_LONDON_NY:  return clrLime;  // BEST for scalping
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
   
   // Check if in first N minutes (skip)
   if(hour == startHour && min < InpSessionStartBuffer) return false;
   
   // Check if in last N minutes (skip)
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
   
   // Find next enabled session
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
            // Next day
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
   
   // Determine trading status
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
      g_sessionStatus = "✓ TRADING ACTIVE";
   }
   
   g_currentSession = sessionName;
   g_sessionColor = GetSessionColor(session, enabled && inBuffer);
   
   // Calculate next session if not trading
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
   
   int x = 10;
   int y = 30;
   int lineHeight = 14;
   
   // Clear previous comments
   Comment("");
   
   string status = "";
   
   // Header
   status += "╔══════════════════════════════════════════════════════════╗\n";
   status += "║         MICRO-SCALPER v4.00 - SESSION MONITOR           ║\n";
   status += "╠══════════════════════════════════════════════════════════╣\n";
   
   // Session Status
   string sessionLine = "║ SESSION: " + g_currentSession;
   while(StringLen(sessionLine) < 58) sessionLine += " ";
   sessionLine += "║\n";
   status += sessionLine;
   
   string statusLine = "║ STATUS:  " + g_sessionStatus;
   while(StringLen(statusLine) < 58) statusLine += " ";
   statusLine += "║\n";
   status += statusLine;
   
   // Trade Allowed Indicator
   string tradeLine = "║ TRADING: " + (g_isTradeAllowed ? "✓ ENABLED" : "✗ DISABLED");
   if(!g_isTradeAllowed && g_nextSession != "")
   {
      int minsToNext = (int)((g_nextSessionTime - now) / 60);
      if(minsToNext < 60)
         tradeLine += " (Next: " + g_nextSession + " in " + IntegerToString(minsToNext) + "m)";
      else
         tradeLine += " (Next: " + g_nextSession + ")";
   }
   while(StringLen(tradeLine) < 58) tradeLine += " ";
   tradeLine += "║\n";
   status += tradeLine;
   
   status += "╠══════════════════════════════════════════════════════════╣\n";
   
   // Market Info
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   string priceLine = "║ PRICE: " + DoubleToString(bid, 2) + " | SPREAD: " + IntegerToString(spread) + " pts";
   if(spread > InpMaxSpreadPoints) priceLine += " ⚠ HIGH";
   while(StringLen(priceLine) < 58) priceLine += " ";
   priceLine += "║\n";
   status += priceLine;
   
   // Account Info
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   string accLine = "║ BALANCE: $" + DoubleToString(balance, 2) + " | EQUITY: $" + DoubleToString(equity, 2);
   while(StringLen(accLine) < 58) accLine += " ";
   accLine += "║\n";
   status += accLine;
   
   // Daily Stats
   UpdateDailyStats();
   string statsLine = "║ TODAY: " + IntegerToString(g_winsToday) + "W/" + 
                     IntegerToString(g_lossesToday) + "L | P&L: $" + DoubleToString(g_profitToday, 2);
   if(InpMaxDailyProfit > 0)
      statsLine += " | Limit: " + IntegerToString(g_winsToday) + "/" + IntegerToString(InpMaxDailyProfit);
   while(StringLen(statsLine) < 58) statsLine += " ";
   statsLine += "║\n";
   status += statsLine;
   
   status += "╠══════════════════════════════════════════════════════════╣\n";
   
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
         string posLine = "║ POSITION: #" + IntegerToString((int)ticket) + " " + posType + " " + 
                         DoubleToString(lots, 2) + " lots";
         while(StringLen(posLine) < 58) posLine += " ";
         posLine += "║\n";
         status += posLine;
         
         string pnlLine = "║ P&L: $" + DoubleToString(profit, 2) + " | Points: " + DoubleToString(profitPts, 0);
         if(profitPts >= InpBE_Trigger) pnlLine += " [BE READY]";
         if(profitPts >= InpTrail_Start) pnlLine += " [TRAILING]";
         while(StringLen(pnlLine) < 58) pnlLine += " ";
         pnlLine += "║\n";
         status += pnlLine;
      }
   }
   else
   {
      string noPosLine = "║ POSITION: No active trades";
      while(StringLen(noPosLine) < 58) noPosLine += " ";
      noPosLine += "║\n";
      status += noPosLine;
   }
   
   status += "╚══════════════════════════════════════════════════════════╝";
   
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
   
   // Check max trades
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
   {
      DebugLog("✋ Daily trade limit reached (" + IntegerToString(g_tradesToday) + "/" + 
         IntegerToString(InpMaxTradesPerDay) + ") - DONE FOR TODAY");
      return false;
   }
   
   // Check max losses (count based)
   if(InpMaxDailyLoss > 0 && g_lossesToday >= InpMaxDailyLoss)
   {
      DebugLog("🛑 Daily loss limit reached (" + IntegerToString(g_lossesToday) + 
         " losses) - STOP TRADING to protect capital!");
      return false;
   }
   
   // Check max losses (dollar based)
   if(InpMaxDailyLossDollars > 0 && g_profitToday <= -InpMaxDailyLossDollars)
   {
      DebugLog("🛑 Daily loss limit reached ($" + DoubleToString(-g_profitToday, 2) + 
         ") - STOP TRADING!");
      return false;
   }
   
   // Check max wins (take profit for the day)
   if(InpMaxDailyProfit > 0 && g_winsToday >= InpMaxDailyProfit)
   {
      DebugLog("🎯 Daily profit target reached (" + IntegerToString(g_winsToday) + 
         " wins, $" + DoubleToString(g_profitToday, 2) + ") - DONE FOR TODAY! ✓");
      return false;
   }
   
   // Check max profit (dollar based)
   if(InpMaxDailyProfitDollars > 0 && g_profitToday >= InpMaxDailyProfitDollars)
   {
      DebugLog("🎯 Daily profit target reached ($" + DoubleToString(g_profitToday, 2) + 
         ") - PROTECT YOUR GAINS! ✓");
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
         DebugLog("✗ Candle too weak: " + DoubleToString(bodyPercent, 1) + "% body");
      return false;
   }
   
   if(isBuy && close <= open)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ BUY but bearish candle");
      return false;
   }
   
   if(!isBuy && close >= open)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ SELL but bullish candle");
      return false;
   }
   
   return true;
}

bool CheckBuySignal()
{
   double fe, se, rs, at, mom, adx;
   if(!GetIndicatorValues(fe, se, rs, at, mom, adx)) return false;

   double fast[5], slow[5];
   if(CopyBuffer(hFastEma, 0, 0, 5, fast) < 5) return false;
   if(CopyBuffer(hSlowEma, 0, 0, 5, slow) < 5) return false;

   // ATR Volatility Check
   double atrPts = at / _Point;
   if(InpAvoidHighVolatility && atrPts > InpMaxATRPoints)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ BUY: High volatility (ATR=" + DoubleToString(atrPts, 0) + ")");
      return false;
   }
   if(InpAvoidLowVolatility && atrPts < InpMinATRPoints)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ BUY: Low volatility (ATR=" + DoubleToString(atrPts, 0) + ")");
      return false;
   }

   // ADX Trend Strength (CRITICAL)
   if(InpAvoidChoppyMarket && adx < InpMinADX)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ BUY: Weak trend (ADX=" + DoubleToString(adx, 1) + " < " + DoubleToString(InpMinADX, 1) + ")");
      return false;
   }

   // EMA Trend Alignment (CRITICAL)
   if(InpRequireTrendAlignment && fast[1] <= slow[1])
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ BUY: No trend (Fast <= Slow)");
      return false;
   }

   // EMA Distance Check (NEW - ensures clear trend)
   if(InpRequireEMADistance)
   {
      double emaDistance = (fast[1] - slow[1]) / _Point;
      if(emaDistance < InpMinEMADistancePoints)
      {
         if(InpLogSignalAnalysis)
            DebugLog("✗ BUY: EMAs too close (" + DoubleToString(emaDistance, 1) + " pts)");
         return false;
      }
   }

   // Momentum (CRITICAL)
   if(InpRequireStrongMomentum && mom < InpMinMomentumThreshold)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ BUY: Weak momentum (" + DoubleToString(mom, 5) + ")");
      return false;
   }

   // RSI Confirmation (STRICT)
   if(InpRequireRSIConfirmation)
   {
      if(rs < InpRSI_BuyMin || rs > InpRSI_BuyMax)
      {
         if(InpLogSignalAnalysis)
            DebugLog("✗ BUY: RSI out of zone (" + DoubleToString(rs, 1) + ")");
         return false;
      }
   }

   // Candle Pattern
   if(!CheckCandlePattern(true)) return false;

   // Entry Pattern
   bool crossUp = (fast[2] <= slow[2]) && (fast[1] > slow[1]);
   bool strongTrend = (fast[1] > slow[1]) && (fast[1] > fast[2]) && (slow[1] > slow[2]);
   
   if(!crossUp && !strongTrend)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ BUY: No clear entry pattern");
      return false;
   }

   if(InpLogSignalAnalysis)
   {
      string pattern = crossUp ? "CROSS↑" : "TREND↑";
      DebugLog("✓ BUY SIGNAL: " + pattern + " | RSI=" + DoubleToString(rs, 1) + 
         " ADX=" + DoubleToString(adx, 1) + " ATR=" + DoubleToString(atrPts, 0));
   }

   return true;
}

bool CheckSellSignal()
{
   double fe, se, rs, at, mom, adx;
   if(!GetIndicatorValues(fe, se, rs, at, mom, adx)) return false;

   double fast[5], slow[5];
   if(CopyBuffer(hFastEma, 0, 0, 5, fast) < 5) return false;
   if(CopyBuffer(hSlowEma, 0, 0, 5, slow) < 5) return false;

   double atrPts = at / _Point;
   if(InpAvoidHighVolatility && atrPts > InpMaxATRPoints)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ SELL: High volatility");
      return false;
   }
   if(InpAvoidLowVolatility && atrPts < InpMinATRPoints)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ SELL: Low volatility");
      return false;
   }

   if(InpAvoidChoppyMarket && adx < InpMinADX)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ SELL: Weak trend (ADX=" + DoubleToString(adx, 1) + ")");
      return false;
   }

   if(InpRequireTrendAlignment && fast[1] >= slow[1])
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ SELL: No trend (Fast >= Slow)");
      return false;
   }

   if(InpRequireEMADistance)
   {
      double emaDistance = (slow[1] - fast[1]) / _Point;
      if(emaDistance < InpMinEMADistancePoints)
      {
         if(InpLogSignalAnalysis)
            DebugLog("✗ SELL: EMAs too close (" + DoubleToString(emaDistance, 1) + " pts)");
         return false;
      }
   }

   if(InpRequireStrongMomentum && mom > -InpMinMomentumThreshold)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ SELL: Weak momentum");
      return false;
   }

   if(InpRequireRSIConfirmation)
   {
      if(rs < InpRSI_SellMin || rs > InpRSI_SellMax)
      {
         if(InpLogSignalAnalysis)
            DebugLog("✗ SELL: RSI out of zone (" + DoubleToString(rs, 1) + ")");
         return false;
      }
   }

   if(!CheckCandlePattern(false)) return false;

   bool crossDown = (fast[2] >= slow[2]) && (fast[1] < slow[1]);
   bool strongTrend = (fast[1] < slow[1]) && (fast[1] < fast[2]) && (slow[1] < slow[2]);
   
   if(!crossDown && !strongTrend)
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ SELL: No clear entry pattern");
      return false;
   }

   if(InpLogSignalAnalysis)
   {
      string pattern = crossDown ? "CROSS↓" : "TREND↓";
      DebugLog("✓ SELL SIGNAL: " + pattern + " | RSI=" + DoubleToString(rs, 1) + 
         " ADX=" + DoubleToString(adx, 1) + " ATR=" + DoubleToString(atrPts, 0));
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
   
   DebugLog("▶ OPENING " + side + " | Lot=0.01 Entry=" + DoubleToString(entry, _Digits) + 
      " SL=" + IntegerToString(slPts) + "pts TP=" + IntegerToString(tpPts) + "pts Spread=" + IntegerToString(spread));

   bool ok = false;
   if(isBuy) ok = trade.Buy(lots, _Symbol, entry, sl, tp, "Micro$10 BUY");
   else      ok = trade.Sell(lots, _Symbol, entry, sl, tp, "Micro$10 SELL");

   if(ok)
   {
      g_lastTradeTime = TimeCurrent();
      ResetDailyCountersIfNeeded();
      g_tradesToday++;
      
      DebugLog("✓ TRADE OPENED " + side + " #" + IntegerToString(trade.ResultOrder()));
      DebugLog("  Today: " + IntegerToString(g_tradesToday) + " trades | " + 
         IntegerToString(g_winsToday) + "W/" + IntegerToString(g_lossesToday) + "L | " +
         "P&L: $" + DoubleToString(g_profitToday, 2) + " | Balance: $" + DoubleToString(balance, 2));
   }
   else
   {
      DebugLog("✗ FAILED " + side + " | Error: " + IntegerToString(trade.ResultRetcode()) + 
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
                  DebugLog("  ✓ Partial close " + DoubleToString(closeVol, 2) + " lots at +" + 
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
            DebugLog("  ✓ SL adjusted to " + DoubleToString(newSL, _Digits) + 
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
      hRsi == INVALID_HANDLE || hAtr == INVALID_HANDLE ||
      hMomentum == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
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

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   Print("╔══════════════════════════════════════════════════════════╗");
   Print("║      MICRO-ACCOUNT SCALPER v4.00 INITIALIZED            ║");
   Print("║      Enhanced Session Management Edition                ║");
   Print("╚══════════════════════════════════════════════════════════╝");
   Print("💰 Account Balance: $", DoubleToString(balance, 2));
   Print("📊 Strategy: Ultra-Conservative (80%+ Win Rate Target)");
   Print("⚙️  Lot Size: 0.01 (FIXED)");
   Print("🎯 Risk/Trade: ~$1.00 | Profit/Trade: ~$1.50");
   Print("🛡️  Daily Limits: Max 2 losses OR 5 wins");
   Print("📉 SL: ", InpScalpSL_Points, " pts | 📈 TP: ", InpScalpTP_Points, " pts");
   Print("📊 Spread Limit: ", InpMaxSpreadPoints, " pts (STRICT)");
   Print("══════════════════════════════════════════════════════════");
   Print("🕐 SESSION SCHEDULE:");
   Print("   London-NY Overlap: 12:00-16:00 GMT [PEAK SCALPING]");
   Print("   London Session:    08:00-12:00 GMT [Trend Setup]");
   Print("   New York Session:  13:00-21:00 GMT [US Data]");
   Print("══════════════════════════════════════════════════════════");
   
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
   Comment(""); // Clear chart comments
   
   Print("Micro-Account Scalper deinitialized");
   Print("Final Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
}

void OnTick()
{
   if(!IsXAUUSD(_Symbol)) return;

   // Always update display
   DisplayStatus();

   ManagePosition();

   if(!IsNewBar()) return;

   int spreadPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(!SpreadOK())
   {
      if(InpLogSignalAnalysis)
         DebugLog("✗ SKIP: Spread too high (" + IntegerToString(spreadPts) + " > " + 
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
      if(remaining > 0)
         DebugLog("⏳ Cooldown: " + IntegerToString(remaining) + "s remaining");
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
      DebugLog("✗ Conflicting signals - skipping");
      return;
   }

   if(buySignal) OpenTrade(true);
   if(sellSignal) OpenTrade(false);
}
//+------------------------------------------------------------------+
