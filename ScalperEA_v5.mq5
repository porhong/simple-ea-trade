//+------------------------------------------------------------------+
//|                                      ScalperEA_v5_Countdown.mq5 |
//|              Universal Scalper with Countdown Dashboard         |
//|              Real-time Timer Display & Status Updates           |
//+------------------------------------------------------------------+
#property strict
#property version   "5.10"
#property description "Universal Scalper - Countdown Dashboard Edition"
#property description "Real-time cooldown and delay timers"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        TradeManager;
CPositionInfo PositionInfo;

//+------------------------------------------------------------------+
//| SECTION 1: CORE SETTINGS                                         |
//+------------------------------------------------------------------+
input group    "=== CORE SETTINGS ==="
input string   InpStrategyName     = "Scalper_v5";    // Strategy identifier
input long     InpMagicNumber      = 20260211;        // Unique EA identifier
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;       // Trading timeframe
input int      InpStartupDelaySec  = 300;             // Startup delay in seconds (0=disabled)

//+------------------------------------------------------------------+
//| SECTION 2: ACCOUNT & POSITION SETTINGS                           |
//+------------------------------------------------------------------+
input group    "=== ACCOUNT & POSITION SETTINGS ==="
input double   InpBaseLotSize      = 0.02;            // Base lot size per trade
input double   InpMaxLotSize       = 0.03;            // Maximum allowed lot size
input double   InpMinLotSize       = 0.01;            // Minimum allowed lot size
input bool     InpOneTradeAtATime  = true;            // Only one position open

//+------------------------------------------------------------------+
//| SECTION 3: RISK MANAGEMENT                                       |
//+------------------------------------------------------------------+
input group    "=== RISK MANAGEMENT ==="
input int      InpStopLossPoints   = 150;             // Stop loss in points
input int      InpTakeProfitPoints = 200;             // Take profit in points

input int      InpDailyMaxLossCount   = 3;            // Max losing trades per day
input int      InpDailyMaxWinCount    = 8;            // Max winning trades per day
input double   InpDailyMaxLossAmount  = 5.0;          // Max daily loss in $
input double   InpDailyMaxWinAmount   = 10.0;         // Max daily profit in $
input int      InpMaxTradesPerDay     = 15;           // Max total trades per day

//+------------------------------------------------------------------+
//| SECTION 4: PARTIAL CLOSE SETTINGS                                |
//+------------------------------------------------------------------+
input group    "=== PARTIAL CLOSE SETTINGS ==="
input bool     InpEnablePartialClose   = true;        // Enable partial profit taking
input int      InpPartialCloseTrigger  = 100;         // Points to trigger partial close
input double   InpPartialClosePercent  = 50.0;        // % of position to close

//+------------------------------------------------------------------+
//| SECTION 5: BREAKEVEN & TRAILING SETTINGS                         |
//+------------------------------------------------------------------+
input group    "=== BREAKEVEN & TRAILING SETTINGS ==="
input bool     InpEnableBreakeven    = true;          // Move SL to breakeven
input int      InpBreakevenTrigger   = 60;            // Points to trigger BE
input int      InpBreakevenOffset    = 5;             // BE offset in points

input bool     InpEnableTrailing     = true;          // Enable trailing stop
input int      InpTrailingTrigger    = 100;           // Points to start trailing
input int      InpTrailingDistance   = 40;            // Trailing distance in points

//+------------------------------------------------------------------+
//| SECTION 6: SPREAD & TIMING FILTERS                               |
//+------------------------------------------------------------------+
input group    "=== SPREAD & TIMING FILTERS ==="
input int      InpMaxSpreadPoints    = 80;            // Max allowed spread
input int      InpSlippagePoints     = 10;            // Max slippage allowed
input int      InpTradeCooldownSec   = 300;           // Seconds between trades

//+------------------------------------------------------------------+
//| SECTION 7: SESSION SETTINGS                                      |
//+------------------------------------------------------------------+
input group    "=== SESSION SETTINGS ==="
input bool     InpUseSessionFilter   = true;          // Enable session filtering
input bool     InpTradeAsianSession      = false;     // Trade 00:00-08:00 GMT
input bool     InpTradePreLondonSession  = true;      // Trade 07:00-08:00 GMT
input bool     InpTradeLondonSession     = true;      // Trade 08:00-12:00 GMT
input bool     InpTradeLondonNYOverlap   = true;      // Trade 12:00-16:00 GMT
input bool     InpTradeNewYorkSession    = true;      // Trade 13:00-21:00 GMT
input int      InpSessionStartBuffer = 5;             // Minutes to skip at session start
input int      InpSessionEndBuffer   = 5;             // Minutes to skip before session end

//+------------------------------------------------------------------+
//| SECTION 8: INDICATOR PARAMETERS                                  |
//+------------------------------------------------------------------+
input group    "=== INDICATOR PARAMETERS ==="
input int      InpFastMAPeriod       = 8;             // Fast MA period
input int      InpSlowMAPeriod       = 18;            // Slow MA period
input int      InpRSIPeriod          = 12;            // RSI period
input int      InpATRPeriod          = 10;            // ATR period
input int      InpMomentumPeriod     = 10;            // Momentum period
input int      InpADXPeriod          = 14;            // ADX period

//+------------------------------------------------------------------+
//| SECTION 9: ENTRY SIGNAL FILTERS                                  |
//+------------------------------------------------------------------+
input group    "=== ENTRY SIGNAL FILTERS ==="
input bool     InpFilterRequireTrendAlignment = true;   // Require EMA trend alignment
input bool     InpFilterRequireRSI            = true;   // Use RSI filter
input double   InpRSIBuyMin                   = 40.0;   // RSI min for buy
input double   InpRSIBuyMax                   = 70.0;   // RSI max for buy
input double   InpRSISellMin                  = 30.0;   // RSI min for sell
input double   InpRSISellMax                  = 60.0;   // RSI max for sell

input bool     InpFilterRequireADX            = false;  // Use ADX filter
input double   InpADXMinValue                 = 20.0;   // Min ADX for entry

input bool     InpFilterRequireMomentum       = false;  // Use momentum filter
input double   InpMomentumMinValue            = 0.0003; // Min momentum threshold

input bool     InpFilterRequireEMADistance    = false;  // Require EMA separation
input double   InpEMAMinDistancePoints        = 10.0;   // Min EMA distance

input bool     InpFilterRequireCandlePattern  = false;  // Check candle pattern
input double   InpMinCandleBodyPercent        = 30.0;   // Min candle body %

//+------------------------------------------------------------------+
//| SECTION 10: ENTRY PATTERN SETTINGS                               |
//+------------------------------------------------------------------+
input group    "=== ENTRY PATTERN SETTINGS ==="
input bool     InpUseMACrossEntry     = true;         // Use MA crossover entries
input bool     InpUseRSIBounceEntry   = true;         // Use RSI bounce entries
input bool     InpUseTrendFollowEntry = true;         // Use trend following entries
input bool     InpUseMASupportEntry   = true;         // Use MA support/resistance entries

//+------------------------------------------------------------------+
//| SECTION 11: VOLATILITY FILTERS                                   |
//+------------------------------------------------------------------+
input group    "=== VOLATILITY FILTERS ==="
input bool     InpFilterMaxVolatility = false;        // Filter high volatility
input double   InpMaxATRPoints        = 800.0;        // Max ATR allowed
input bool     InpFilterMinVolatility = false;        // Filter low volatility
input double   InpMinATRPoints        = 200.0;        // Min ATR required

//+------------------------------------------------------------------+
//| SECTION 12: DISPLAY SETTINGS                                     |
//+------------------------------------------------------------------+
input group    "=== DISPLAY SETTINGS ==="
input bool     InpEnableDashboard     = true;         // Enable visual dashboard
input bool     InpEnableDebugLog      = true;         // Enable debug logging
input bool     InpLogSignalDetails    = true;         // Log signal analysis
input bool     InpShowDailyStats      = true;         // Show daily statistics
input bool     InpShowAccountWarnings = true;         // Show account warnings
input bool     InpShowSessionInfo     = true;         // Show session info
input bool     InpShowPositionInfo    = true;         // Show position info

// Minimal Color Palette - Professional Dark Theme
input color    InpColorBg           = C'28, 30, 34';    // Background (dark charcoal)
input color    InpColorHeader       = C'38, 40, 46';    // Header (slate gray)
input color    InpColorText         = C'200, 202, 205'; // Text (soft white)
input color    InpColorTextDim      = C'130, 133, 139'; // Dim text (gray)

input color    InpColorActive       = C'46, 120, 80';   // Active/Enabled (muted green)
input color    InpColorDisabled     = C'100, 60, 60';   // Disabled (muted red-gray)
input color    InpColorWarning      = C'160, 130, 60';  // Warning/Waiting (amber)
input color    InpColorCountdown    = C'60, 90, 120';   // Countdown state (blue-gray)

input color    InpColorProfit       = C'50, 130, 80';   // Profit (soft green)
input color    InpColorLoss         = C'130, 60, 60';   // Loss (soft red)
input color    InpColorNeutral      = C'45, 48, 54';    // Neutral panels

input int      InpDashboardX        = 10;            // Dashboard X position
input int      InpDashboardY        = 30;            // Dashboard Y position
input int      InpStatusUpdateSec   = 1;             // Status update interval (seconds)

//+------------------------------------------------------------------+
//| DISPLAY OBJECT NAMES                                             |
//+------------------------------------------------------------------+
#define OBJ_PREFIX      "ScalperV5_"
#define OBJ_BG          OBJ_PREFIX + "BG"
#define OBJ_HEADER      OBJ_PREFIX + "Header"
#define OBJ_SESSION     OBJ_PREFIX + "Session"
#define OBJ_TRADING     OBJ_PREFIX + "Trading"
#define OBJ_PRICE       OBJ_PREFIX + "Price"
#define OBJ_ACCOUNT     OBJ_PREFIX + "Account"
#define OBJ_DAILY       OBJ_PREFIX + "Daily"
#define OBJ_POSITION    OBJ_PREFIX + "Position"
#define OBJ_SIGNAL      OBJ_PREFIX + "Signal"
#define OBJ_COUNTDOWN   OBJ_PREFIX + "Countdown"
#define OBJ_PROGRESS_BG OBJ_PREFIX + "ProgBG"
#define OBJ_PROGRESS_BAR OBJ_PREFIX + "ProgBar"

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+

// Indicator handles
int    g_HandleFastMA    = INVALID_HANDLE;
int    g_HandleSlowMA    = INVALID_HANDLE;
int    g_HandleRSI       = INVALID_HANDLE;
int    g_HandleATR       = INVALID_HANDLE;
int    g_HandleMomentum  = INVALID_HANDLE;
int    g_HandleADX       = INVALID_HANDLE;

// Time tracking
datetime g_LastBarTime      = 0;
datetime g_LastTradeTime    = 0;
datetime g_LastStatusUpdate = 0;
datetime g_EAStartTime      = 0;  // When EA was initialized

// Daily statistics
int     g_DailyTradeCount   = 0;
int     g_DailyWinCount     = 0;
int     g_DailyLossCount    = 0;
double  g_DailyProfit       = 0.0;
int     g_CurrentDayOfYear  = -1;
int     g_SignalCheckCount  = 0;
int     g_LastSignalHour    = -1;

// Session tracking
string  g_CurrentSession    = "NONE";
string  g_SessionStatus     = "WAITING";
bool    g_IsTradingAllowed  = false;
string  g_NextSessionName   = "";
datetime g_NextSessionTime  = 0;

// Countdown tracking
int     g_StartUpRemaining  = 0;     // Seconds remaining for startup
int     g_CooldownRemaining = 0;     // Seconds remaining for cooldown
bool    g_IsInStartup       = false;
bool    g_IsInCooldown      = false;
double  g_CooldownProgress  = 0.0;   // 0.0 to 1.0
double  g_StartupProgress   = 0.0;   // 0.0 to 1.0

// Session enum
enum ENUM_TRADING_SESSION
{
   SESSION_ASIAN,      // 00:00 - 08:00 GMT
   SESSION_PRE_LONDON, // 07:00 - 08:00 GMT
   SESSION_LONDON,     // 08:00 - 12:00 GMT
   SESSION_LONDON_NY,  // 12:00 - 16:00 GMT
   SESSION_NEW_YORK,   // 13:00 - 21:00 GMT
   SESSION_CLOSED      // 21:00 - 00:00 GMT
};

//+------------------------------------------------------------------+
//| UTILITY FUNCTIONS                                                |
//+------------------------------------------------------------------+

void LogMessage(string message)
{
   if(InpEnableDebugLog)
      Print("[", InpStrategyName, "] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " | ", message);
}

bool IsSymbolGold(string symbol)
{
   return (StringFind(symbol, "XAUUSD") >= 0 || StringFind(symbol, "GOLD") >= 0);
}

int GetDayOfYear()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   MqlDateTime jan1 = tm;
   jan1.mon = 1; jan1.day = 1; jan1.hour = 0; jan1.min = 0; jan1.sec = 0;
   datetime jan1Time = StructToTime(jan1);
   return (int)((TimeCurrent() - jan1Time) / 86400);
}

void ResetDailyStatsIfNeeded()
{
   int currentDay = GetDayOfYear();
   if(currentDay != g_CurrentDayOfYear)
   {
      if(g_CurrentDayOfYear != -1 && InpShowDailyStats)
      {
         LogMessage("===== DAILY SUMMARY =====");
         LogMessage("Total Trades: " + IntegerToString(g_DailyTradeCount));
         LogMessage("Wins: " + IntegerToString(g_DailyWinCount) + " | Losses: " + IntegerToString(g_DailyLossCount));
         if(g_DailyTradeCount > 0)
         {
            double winRate = (double)g_DailyWinCount / (double)g_DailyTradeCount * 100.0;
            LogMessage("Win Rate: " + DoubleToString(winRate, 1) + "%");
         }
         LogMessage("Daily P&L: $" + DoubleToString(g_DailyProfit, 2));
         LogMessage("Account Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
         LogMessage("=========================");
      }
      
      g_CurrentDayOfYear = currentDay;
      g_DailyTradeCount = 0;
      g_DailyWinCount = 0;
      g_DailyLossCount = 0;
      g_DailyProfit = 0.0;
      g_SignalCheckCount = 0;
   }
}

void UpdateDailyStatistics()
{
   ResetDailyStatsIfNeeded();
   
   datetime todayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE) + " 00:00:00");
   
   g_DailyWinCount = 0;
   g_DailyLossCount = 0;
   g_DailyProfit = 0.0;
   
   // Track processed positions to avoid double counting partial closes
   ulong processedPositions[100];
   int processedCount = 0;
   
   HistorySelect(todayStart, TimeCurrent());
   int totalDeals = HistoryDealsTotal();
   
   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;
      
      // Filter by symbol and magic
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber) continue;
      
      // Only process close deals
      if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      
      // Get position ID
      ulong positionID = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      
      // Add to daily profit (all deals count for P&L)
      double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      g_DailyProfit += dealProfit + dealCommission + dealSwap;
      
      // Check if position already counted
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
      
      // Calculate total profit for entire position
      double totalPositionProfit = 0;
      for(int k = 0; k < totalDeals; k++)
      {
         ulong checkDeal = HistoryDealGetTicket(k);
         if(checkDeal == 0) continue;
         if(HistoryDealGetInteger(checkDeal, DEAL_POSITION_ID) != positionID) continue;
         if(HistoryDealGetString(checkDeal, DEAL_SYMBOL) != _Symbol) continue;
         if(HistoryDealGetInteger(checkDeal, DEAL_MAGIC) != InpMagicNumber) continue;
         
         totalPositionProfit += HistoryDealGetDouble(checkDeal, DEAL_PROFIT);
         totalPositionProfit += HistoryDealGetDouble(checkDeal, DEAL_COMMISSION);
         totalPositionProfit += HistoryDealGetDouble(checkDeal, DEAL_SWAP);
      }
      
      // Mark as processed
      if(processedCount < 100)
      {
         processedPositions[processedCount] = positionID;
         processedCount++;
      }
      
      // Count as win or loss
      if(totalPositionProfit > 0.01) g_DailyWinCount++;
      else if(totalPositionProfit < -0.01) g_DailyLossCount++;
   }
   
   g_DailyTradeCount = g_DailyWinCount + g_DailyLossCount;
}

bool IsNewBar()
{
   MqlRates rates[2];
   if(CopyRates(_Symbol, InpTimeframe, 0, 2, rates) < 2) return false;
   if(rates[0].time != g_LastBarTime)
   {
      g_LastBarTime = rates[0].time;
      return true;
   }
   return false;
}

bool IsSpreadAcceptable()
{
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   return (currentSpread > 0 && currentSpread <= InpMaxSpreadPoints);
}

double NormalizeLotSize(double lots)
{
   double minVol = 0, maxVol = 0, stepVol = 0;
   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN, minVol);
   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX, maxVol);
   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP, stepVol);

   lots = MathMax(lots, minVol);
   lots = MathMin(lots, maxVol);
   lots = MathMax(lots, InpMinLotSize);
   lots = MathMin(lots, InpMaxLotSize);

   if(stepVol > 0)
      lots = MathFloor(lots / stepVol) * stepVol;

   return lots;
}

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| STARTUP DELAY FUNCTIONS                                          |
//+------------------------------------------------------------------+

bool IsStartupDelayComplete(int &remainingSeconds)
{
   remainingSeconds = 0;
   
   if(InpStartupDelaySec <= 0) 
   {
      g_IsInStartup = false;
      return true;  // Disabled
   }
   if(g_EAStartTime == 0) 
   {
      g_IsInStartup = false;
      return true;  // Not initialized
   }
   
   datetime currentTime = TimeCurrent();
   int elapsedSeconds = (int)(currentTime - g_EAStartTime);
   
   if(elapsedSeconds >= InpStartupDelaySec)
   {
      g_IsInStartup = false;
      g_StartupProgress = 1.0;
      return true;
   }
   
   remainingSeconds = InpStartupDelaySec - elapsedSeconds;
   g_StartUpRemaining = remainingSeconds;
   g_StartupProgress = (double)elapsedSeconds / (double)InpStartupDelaySec;
   g_IsInStartup = true;
   return false;
}

string GetStartupDelayStatus()
{
   int remainingSeconds = 0;
   
   if(InpStartupDelaySec <= 0)
      return "DISABLED";
   
   if(IsStartupDelayComplete(remainingSeconds))
      return "COMPLETE";
   
   int minutes = remainingSeconds / 60;
   int seconds = remainingSeconds % 60;
   
   if(minutes > 0)
      return IntegerToString(minutes) + "m " + IntegerToString(seconds) + "s";
   else
      return IntegerToString(seconds) + "s";
}

//+------------------------------------------------------------------+
//| SESSION MANAGEMENT                                               |
//+------------------------------------------------------------------+

ENUM_TRADING_SESSION GetCurrentSession(int &hour, int &min)
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   hour = tm.hour;
   min = tm.min;
   
   if(hour >= 0 && hour < 7)       return SESSION_ASIAN;
   else if(hour >= 7 && hour < 8)  return SESSION_PRE_LONDON;
   else if(hour >= 8 && hour < 12) return SESSION_LONDON;
   else if(hour >= 12 && hour < 16) return SESSION_LONDON_NY;
   else if(hour >= 16 && hour < 21) return SESSION_NEW_YORK;
   else return SESSION_CLOSED;
}

string GetSessionName(ENUM_TRADING_SESSION session)
{
   switch(session)
   {
      case SESSION_ASIAN:      return "ASIAN";
      case SESSION_PRE_LONDON: return "PRE-LONDON";
      case SESSION_LONDON:     return "LONDON";
      case SESSION_LONDON_NY:  return "LONDON-NY";
      case SESSION_NEW_YORK:   return "NEW-YORK";
      case SESSION_CLOSED:     return "CLOSED";
      default:                 return "UNKNOWN";
   }
}

bool IsSessionEnabled(ENUM_TRADING_SESSION session)
{
   switch(session)
   {
      case SESSION_ASIAN:      return InpTradeAsianSession;
      case SESSION_PRE_LONDON: return InpTradePreLondonSession;
      case SESSION_LONDON:     return InpTradeLondonSession;
      case SESSION_LONDON_NY:  return InpTradeLondonNYOverlap;
      case SESSION_NEW_YORK:   return InpTradeNewYorkSession;
      case SESSION_CLOSED:     return false;
      default:                 return false;
   }
}

bool IsInSessionBuffer(int hour, int min, ENUM_TRADING_SESSION session)
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

void UpdateSessionStatus()
{
   if(!InpShowSessionInfo && !InpEnableDashboard) return;
   
   int hour, min;
   ENUM_TRADING_SESSION session = GetCurrentSession(hour, min);
   string sessionName = GetSessionName(session);
   
   bool enabled = IsSessionEnabled(session);
   bool inBuffer = IsInSessionBuffer(hour, min, session);
   bool spreadOk = IsSpreadAcceptable();
   
   g_IsTradingAllowed = false;
   g_SessionStatus = "BLOCKED";
   
   // Priority: Startup > Cooldown > Session > Spread
   if(g_IsInStartup)
   {
      g_SessionStatus = "STARTUP";
   }
   else if(g_IsInCooldown)
   {
      g_SessionStatus = "COOLDOWN";
   }
   else if(!InpUseSessionFilter)
   {
      g_IsTradingAllowed = true;
      g_SessionStatus = "ACTIVE";
   }
   else if(!enabled)
   {
      g_SessionStatus = "DISABLED";
   }
   else if(!inBuffer)
   {
      g_SessionStatus = "BUFFER";
   }
   else if(!spreadOk)
   {
      g_SessionStatus = "HIGH-SPREAD";
   }
   else
   {
      g_IsTradingAllowed = true;
      g_SessionStatus = "ACTIVE";
   }
   
   g_CurrentSession = sessionName;
}

bool IsTradingSessionOK()
{
   if(!InpUseSessionFilter) return true;
   
   int hour, min;
   ENUM_TRADING_SESSION session = GetCurrentSession(hour, min);
   
   if(!IsSessionEnabled(session)) return false;
   if(!IsInSessionBuffer(hour, min, session)) return false;
   
   return true;
}

bool IsCooldownComplete()
{
   if(InpTradeCooldownSec <= 0) 
   {
      g_IsInCooldown = false;
      g_CooldownProgress = 1.0;
      return true;
   }
   
   int elapsed = (int)(TimeCurrent() - g_LastTradeTime);
   if(elapsed >= InpTradeCooldownSec)
   {
      g_IsInCooldown = false;
      g_CooldownProgress = 1.0;
      g_CooldownRemaining = 0;
      return true;
   }
   
   g_CooldownRemaining = InpTradeCooldownSec - elapsed;
   g_CooldownProgress = (double)elapsed / (double)InpTradeCooldownSec;
   g_IsInCooldown = true;
   return false;
}

bool AreDailyLimitsOK()
{
   ResetDailyStatsIfNeeded();
   UpdateDailyStatistics();
   
   if(InpMaxTradesPerDay > 0 && g_DailyTradeCount >= InpMaxTradesPerDay)
   {
      LogMessage("[LIMIT] Daily trade limit reached: " + IntegerToString(g_DailyTradeCount));
      return false;
   }
   
   if(InpDailyMaxLossCount > 0 && g_DailyLossCount >= InpDailyMaxLossCount)
   {
      LogMessage("[STOP] Daily loss count limit reached: " + IntegerToString(g_DailyLossCount));
      return false;
   }
   
   if(InpDailyMaxLossAmount > 0 && g_DailyProfit <= -InpDailyMaxLossAmount)
   {
      LogMessage("[STOP] Daily loss amount limit reached: $" + DoubleToString(-g_DailyProfit, 2));
      return false;
   }
   
   if(InpDailyMaxWinCount > 0 && g_DailyWinCount >= InpDailyMaxWinCount)
   {
      LogMessage("[TARGET] Daily win count target reached: " + IntegerToString(g_DailyWinCount));
      return false;
   }
   
   if(InpDailyMaxWinAmount > 0 && g_DailyProfit >= InpDailyMaxWinAmount)
   {
      LogMessage("[TARGET] Daily profit target reached: $" + DoubleToString(g_DailyProfit, 2));
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| INDICATOR FUNCTIONS                                              |
//+------------------------------------------------------------------+

bool GetIndicatorValues(double &fastMA, double &slowMA, double &rsi, double &atr, double &momentum, double &adx)
{
   double bufFast[3], bufSlow[3], bufRSI[3], bufATR[3], bufMom[3], bufADX[3];

   if(CopyBuffer(g_HandleFastMA, 0, 0, 3, bufFast) < 3) return false;
   if(CopyBuffer(g_HandleSlowMA, 0, 0, 3, bufSlow) < 3) return false;
   if(CopyBuffer(g_HandleRSI, 0, 0, 3, bufRSI) < 3) return false;
   if(CopyBuffer(g_HandleATR, 0, 0, 3, bufATR) < 3) return false;
   
   if(g_HandleMomentum != INVALID_HANDLE)
   {
      if(CopyBuffer(g_HandleMomentum, 0, 0, 3, bufMom) < 3) return false;
      momentum = bufMom[1];
   }
   else momentum = 0;
   
   if(g_HandleADX != INVALID_HANDLE)
   {
      if(CopyBuffer(g_HandleADX, 0, 0, 3, bufADX) < 3) return false;
      adx = bufADX[1];
   }
   else adx = 0;

   fastMA = bufFast[1];
   slowMA = bufSlow[1];
   rsi = bufRSI[1];
   atr = bufATR[1];

   return true;
}

bool CheckCandlePattern(bool isBuy)
{
   if(!InpFilterRequireCandlePattern) return true;
   
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
      if(InpLogSignalDetails)
         LogMessage("[FILTER] Candle body too small: " + DoubleToString(bodyPercent, 1) + "%");
      return false;
   }
   
   if(isBuy && close <= open)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] BUY signal but bearish candle");
      return false;
   }
   
   if(!isBuy && close >= open)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] SELL signal but bullish candle");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| SIGNAL CHECK FUNCTIONS                                           |
//+------------------------------------------------------------------+

bool CheckBuySignal()
{
   double fastMA, slowMA, rsi, atr, momentum, adx;
   if(!GetIndicatorValues(fastMA, slowMA, rsi, atr, momentum, adx)) 
   {
      if(InpLogSignalDetails) LogMessage("[ERROR] Failed to get indicator values for BUY");
      return false;
   }

   double fastMAHistory[5], slowMAHistory[5];
   if(CopyBuffer(g_HandleFastMA, 0, 0, 5, fastMAHistory) < 5) return false;
   if(CopyBuffer(g_HandleSlowMA, 0, 0, 5, slowMAHistory) < 5) return false;

   // Track signal checks
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   if(tm.hour != g_LastSignalHour)
   {
      g_LastSignalHour = tm.hour;
      g_SignalCheckCount = 0;
   }
   g_SignalCheckCount++;

   // Volatility filters
   double atrPoints = atr / _Point;
   if(InpFilterMaxVolatility && atrPoints > InpMaxATRPoints)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] BUY: High volatility (ATR=" + DoubleToString(atrPoints, 0) + ")");
      return false;
   }
   if(InpFilterMinVolatility && atrPoints < InpMinATRPoints)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] BUY: Low volatility (ATR=" + DoubleToString(atrPoints, 0) + ")");
      return false;
   }

   // ADX filter
   if(InpFilterRequireADX && adx < InpADXMinValue)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] BUY: Weak ADX (" + DoubleToString(adx, 1) + ")");
      return false;
   }

   // Trend alignment
   bool isBullishTrend = fastMAHistory[1] > slowMAHistory[1];
   bool isMACrossUp = (fastMAHistory[2] <= slowMAHistory[2]) && (fastMAHistory[1] > slowMAHistory[1]);
   
   if(InpFilterRequireTrendAlignment && !isBullishTrend)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] BUY: No bullish trend");
      return false;
   }

   // EMA distance filter
   if(InpFilterRequireEMADistance)
   {
      double emaDistance = (fastMAHistory[1] - slowMAHistory[1]) / _Point;
      if(emaDistance < InpEMAMinDistancePoints)
      {
         if(InpLogSignalDetails)
            LogMessage("[FILTER] BUY: EMAs too close (" + DoubleToString(emaDistance, 1) + ")");
         return false;
      }
   }

   // Momentum filter
   if(InpFilterRequireMomentum && momentum < InpMomentumMinValue)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] BUY: Weak momentum");
      return false;
   }

   // RSI filter
   if(InpFilterRequireRSI)
   {
      if(rsi < InpRSIBuyMin || rsi > InpRSIBuyMax)
      {
         if(InpLogSignalDetails)
            LogMessage("[FILTER] BUY: RSI out of range (" + DoubleToString(rsi, 1) + ")");
         return false;
      }
   }

   // Candle pattern
   if(!CheckCandlePattern(true)) return false;

   // Entry patterns
   bool entrySignal = false;
   string patternName = "";
   
   if(InpUseMACrossEntry && isMACrossUp)
   {
      entrySignal = true;
      patternName = "MA-CROSS-UP";
   }
   else if(InpUseRSIBounceEntry && rsi > InpRSIBuyMin && rsi < 55 && isBullishTrend)
   {
      entrySignal = true;
      patternName = "RSI-BOUNCE-UP";
   }
   else if(InpUseTrendFollowEntry && isBullishTrend && fastMAHistory[1] > fastMAHistory[2] && slowMAHistory[1] > slowMAHistory[2])
   {
      entrySignal = true;
      patternName = "TREND-FOLLOW-UP";
   }
   else if(InpUseMASupportEntry && fastMAHistory[1] > slowMAHistory[1] && rsi >= 45 && rsi <= 65)
   {
      entrySignal = true;
      patternName = "MA-SUPPORT-UP";
   }
   
   if(!entrySignal)
   {
      if(InpLogSignalDetails && (g_SignalCheckCount % 10 == 0))
      {
         LogMessage("[FILTER] BUY: No entry pattern | RSI=" + DoubleToString(rsi, 1) + 
            " Trend=" + (isBullishTrend ? "BULL" : "BEAR"));
      }
      return false;
   }

   if(InpLogSignalDetails)
   {
      LogMessage("[SIGNAL] BUY: " + patternName + " | RSI=" + DoubleToString(rsi, 1) + 
         " ADX=" + DoubleToString(adx, 1) + " ATR=" + DoubleToString(atrPoints, 0));
   }

   return true;
}

bool CheckSellSignal()
{
   double fastMA, slowMA, rsi, atr, momentum, adx;
   if(!GetIndicatorValues(fastMA, slowMA, rsi, atr, momentum, adx)) 
   {
      if(InpLogSignalDetails) LogMessage("[ERROR] Failed to get indicator values for SELL");
      return false;
   }

   double fastMAHistory[5], slowMAHistory[5];
   if(CopyBuffer(g_HandleFastMA, 0, 0, 5, fastMAHistory) < 5) return false;
   if(CopyBuffer(g_HandleSlowMA, 0, 0, 5, slowMAHistory) < 5) return false;

   // Track signal checks
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   if(tm.hour != g_LastSignalHour)
   {
      g_LastSignalHour = tm.hour;
      g_SignalCheckCount = 0;
   }
   g_SignalCheckCount++;

   // Volatility filters
   double atrPoints = atr / _Point;
   if(InpFilterMaxVolatility && atrPoints > InpMaxATRPoints)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] SELL: High volatility");
      return false;
   }
   if(InpFilterMinVolatility && atrPoints < InpMinATRPoints)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] SELL: Low volatility");
      return false;
   }

   // ADX filter
   if(InpFilterRequireADX && adx < InpADXMinValue)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] SELL: Weak ADX (" + DoubleToString(adx, 1) + ")");
      return false;
   }

   // Trend alignment
   bool isBearishTrend = fastMAHistory[1] < slowMAHistory[1];
   bool isMACrossDown = (fastMAHistory[2] >= slowMAHistory[2]) && (fastMAHistory[1] < slowMAHistory[1]);
   
   if(InpFilterRequireTrendAlignment && !isBearishTrend)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] SELL: No bearish trend");
      return false;
   }

   // EMA distance filter
   if(InpFilterRequireEMADistance)
   {
      double emaDistance = (slowMAHistory[1] - fastMAHistory[1]) / _Point;
      if(emaDistance < InpEMAMinDistancePoints)
      {
         if(InpLogSignalDetails)
            LogMessage("[FILTER] SELL: EMAs too close (" + DoubleToString(emaDistance, 1) + ")");
         return false;
      }
   }

   // Momentum filter
   if(InpFilterRequireMomentum && momentum > -InpMomentumMinValue)
   {
      if(InpLogSignalDetails)
         LogMessage("[FILTER] SELL: Weak momentum");
      return false;
   }

   // RSI filter
   if(InpFilterRequireRSI)
   {
      if(rsi < InpRSISellMin || rsi > InpRSISellMax)
      {
         if(InpLogSignalDetails)
            LogMessage("[FILTER] SELL: RSI out of range (" + DoubleToString(rsi, 1) + ")");
         return false;
      }
   }

   // Candle pattern
   if(!CheckCandlePattern(false)) return false;

   // Entry patterns
   bool entrySignal = false;
   string patternName = "";
   
   if(InpUseMACrossEntry && isMACrossDown)
   {
      entrySignal = true;
      patternName = "MA-CROSS-DOWN";
   }
   else if(InpUseRSIBounceEntry && rsi < InpRSISellMax && rsi > 45 && isBearishTrend)
   {
      entrySignal = true;
      patternName = "RSI-BOUNCE-DOWN";
   }
   else if(InpUseTrendFollowEntry && isBearishTrend && fastMAHistory[1] < fastMAHistory[2] && slowMAHistory[1] < slowMAHistory[2])
   {
      entrySignal = true;
      patternName = "TREND-FOLLOW-DOWN";
   }
   else if(InpUseMASupportEntry && fastMAHistory[1] < slowMAHistory[1] && rsi >= 35 && rsi <= 55)
   {
      entrySignal = true;
      patternName = "MA-RESIST-DOWN";
   }
   
   if(!entrySignal)
   {
      if(InpLogSignalDetails && (g_SignalCheckCount % 10 == 0))
      {
         LogMessage("[FILTER] SELL: No entry pattern | RSI=" + DoubleToString(rsi, 1) + 
            " Trend=" + (isBearishTrend ? "BEAR" : "BULL"));
      }
      return false;
   }

   if(InpLogSignalDetails)
   {
      LogMessage("[SIGNAL] SELL: " + patternName + " | RSI=" + DoubleToString(rsi, 1) + 
         " ADX=" + DoubleToString(adx, 1) + " ATR=" + DoubleToString(atrPoints, 0));
   }

   return true;
}

//+------------------------------------------------------------------+
//| TRADE EXECUTION                                                  |
//+------------------------------------------------------------------+

bool ExecuteTrade(bool isBuy)
{
   double lotSize = NormalizeLotSize(InpBaseLotSize);
   if(lotSize <= 0)
   {
      LogMessage("[ERROR] Invalid lot size");
      return false;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entryPrice = isBuy ? ask : bid;

   double stopLoss = 0, takeProfit = 0;
   if(isBuy)
   {
      stopLoss = entryPrice - InpStopLossPoints * _Point;
      takeProfit = entryPrice + InpTakeProfitPoints * _Point;
   }
   else
   {
      stopLoss = entryPrice + InpStopLossPoints * _Point;
      takeProfit = entryPrice - InpTakeProfitPoints * _Point;
   }

   TradeManager.SetExpertMagicNumber(InpMagicNumber);
   TradeManager.SetDeviationInPoints(InpSlippagePoints);

   string side = isBuy ? "BUY" : "SELL";
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   LogMessage("[OPEN] " + side + " | Lot=" + DoubleToString(lotSize, 2) + 
      " Entry=" + DoubleToString(entryPrice, _Digits) + 
      " SL=" + IntegerToString(InpStopLossPoints) + " TP=" + IntegerToString(InpTakeProfitPoints) + 
      " Spread=" + IntegerToString(currentSpread));

   bool success = false;
   if(isBuy) success = TradeManager.Buy(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, InpStrategyName + " BUY");
   else      success = TradeManager.Sell(lotSize, _Symbol, entryPrice, stopLoss, takeProfit, InpStrategyName + " SELL");

   if(success)
   {
      g_LastTradeTime = TimeCurrent();
      ResetDailyStatsIfNeeded();
      g_DailyTradeCount++;
      
      LogMessage("[SUCCESS] " + side + " opened #" + IntegerToString(TradeManager.ResultOrder()));
   }
   else
   {
      LogMessage("[FAILED] " + side + " | Error: " + IntegerToString(TradeManager.ResultRetcode()) + 
         " - " + TradeManager.ResultRetcodeDescription());
   }
   
   return success;
}

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT                                              |
//+------------------------------------------------------------------+

void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double positionVolume = PositionGetDouble(POSITION_VOLUME);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentPrice = (positionType == POSITION_TYPE_BUY) ? bid : ask;

      double profitPoints = 0;
      if(positionType == POSITION_TYPE_BUY) profitPoints = (currentPrice - entryPrice) / _Point;
      if(positionType == POSITION_TYPE_SELL) profitPoints = (entryPrice - currentPrice) / _Point;

      // Partial close
      if(InpEnablePartialClose && profitPoints >= InpPartialCloseTrigger)
      {
         string comment = PositionGetString(POSITION_COMMENT);
         if(StringFind(comment, "PARTIAL") < 0)
         {
            double closeVolume = NormalizeLotSize(positionVolume * InpPartialClosePercent / 100.0);
            if(closeVolume >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
               TradeManager.SetExpertMagicNumber(InpMagicNumber);
               if(TradeManager.PositionClosePartial(ticket, closeVolume))
               {
                  LogMessage("[PARTIAL] Closed " + DoubleToString(closeVolume, 2) + " lots at +" + 
                     DoubleToString(profitPoints, 0) + " points");
               }
            }
         }
      }

      double newSL = currentSL;

      // Breakeven
      if(InpEnableBreakeven && profitPoints >= InpBreakevenTrigger)
      {
         if(positionType == POSITION_TYPE_BUY)
         {
            double bePrice = entryPrice + InpBreakevenOffset * _Point;
            if(currentSL < bePrice || currentSL == 0.0) newSL = bePrice;
         }
         else
         {
            double bePrice = entryPrice - InpBreakevenOffset * _Point;
            if(currentSL > bePrice || currentSL == 0.0) newSL = bePrice;
         }
      }

      // Trailing stop
      if(InpEnableTrailing && profitPoints >= InpTrailingTrigger)
      {
         if(positionType == POSITION_TYPE_BUY)
         {
            double trailSL = currentPrice - InpTrailingDistance * _Point;
            if(trailSL > newSL) newSL = trailSL;
         }
         else
         {
            double trailSL = currentPrice + InpTrailingDistance * _Point;
            if(trailSL < newSL || newSL == 0.0) newSL = trailSL;
         }
      }

      // Update SL if changed
      if(newSL != currentSL && MathAbs(newSL - currentSL) > _Point * 3)
      {
         TradeManager.SetExpertMagicNumber(InpMagicNumber);
         if(TradeManager.PositionModify(ticket, newSL, currentTP))
         {
            LogMessage("[MODIFY] SL adjusted to " + DoubleToString(newSL, _Digits) + 
               " (profit: +" + DoubleToString(profitPoints, 0) + " points)");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| DISPLAY FUNCTIONS                                                |
//+------------------------------------------------------------------+

void CreateDashboardObjects()
{
   if(!InpEnableDashboard) return;
   
   int x = InpDashboardX;
   int y = InpDashboardY;
   int width = 280;
   int rowHeight = 22;
   int headerHeight = 28;
   int progressHeight = 4;
   
   // Main Background
   if(ObjectFind(0, OBJ_BG) < 0)
   {
      ObjectCreate(0, OBJ_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, OBJ_BG, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_YSIZE, headerHeight + (rowHeight * 7) + progressHeight + 12);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_BGCOLOR, InpColorBg);
   ObjectSetInteger(0, OBJ_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   
   // Header
   CreateEditObject(OBJ_HEADER, x + 2, y + 2, width - 4, headerHeight - 4, 
                    InpColorHeader, InpColorText, ALIGN_CENTER, 
                    "  " + InpStrategyName + "  ", 9, true);
   
   int currentY = y + headerHeight;
   
   // Session Status Row
   CreateEditObject(OBJ_SESSION, x + 2, currentY + 2, width - 4, rowHeight - 4,
                    InpColorNeutral, InpColorTextDim, ALIGN_LEFT, " Initializing...", 8);
   
   currentY += rowHeight;
   
   // Trading Status Row
   CreateEditObject(OBJ_TRADING, x + 2, currentY + 2, 90, rowHeight - 4,
                    InpColorDisabled, InpColorText, ALIGN_CENTER, " STANDBY ", 8, true);
   
   CreateEditObject(OBJ_PRICE, x + 94, currentY + 2, width - 96, rowHeight - 4,
                    InpColorNeutral, InpColorTextDim, ALIGN_LEFT, " -- ", 8);
   
   currentY += rowHeight;
   
   // Countdown / Timer Row (NEW)
   CreateEditObject(OBJ_COUNTDOWN, x + 2, currentY + 2, width - 4, rowHeight - 4,
                    InpColorNeutral, InpColorTextDim, ALIGN_CENTER, " Ready ", 8, true);
   
   currentY += rowHeight;
   
   // Progress Bar Background (NEW)
   if(ObjectFind(0, OBJ_PROGRESS_BG) < 0)
   {
      ObjectCreate(0, OBJ_PROGRESS_BG, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, OBJ_PROGRESS_BG, OBJPROP_XDISTANCE, x + 2);
   ObjectSetInteger(0, OBJ_PROGRESS_BG, OBJPROP_YDISTANCE, currentY + 2);
   ObjectSetInteger(0, OBJ_PROGRESS_BG, OBJPROP_XSIZE, width - 4);
   ObjectSetInteger(0, OBJ_PROGRESS_BG, OBJPROP_YSIZE, progressHeight);
   ObjectSetInteger(0, OBJ_PROGRESS_BG, OBJPROP_BGCOLOR, C'60, 60, 60');
   ObjectSetInteger(0, OBJ_PROGRESS_BG, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   
   // Progress Bar Fill (NEW)
   if(ObjectFind(0, OBJ_PROGRESS_BAR) < 0)
   {
      ObjectCreate(0, OBJ_PROGRESS_BAR, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   }
   ObjectSetInteger(0, OBJ_PROGRESS_BAR, OBJPROP_XDISTANCE, x + 2);
   ObjectSetInteger(0, OBJ_PROGRESS_BAR, OBJPROP_YDISTANCE, currentY + 2);
   ObjectSetInteger(0, OBJ_PROGRESS_BAR, OBJPROP_XSIZE, 0); // Start at 0
   ObjectSetInteger(0, OBJ_PROGRESS_BAR, OBJPROP_YSIZE, progressHeight);
   ObjectSetInteger(0, OBJ_PROGRESS_BAR, OBJPROP_BGCOLOR, InpColorActive);
   ObjectSetInteger(0, OBJ_PROGRESS_BAR, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   
   currentY += (progressHeight + 2);
   
   // Account Info Row
   CreateEditObject(OBJ_ACCOUNT, x + 2, currentY + 2, width - 4, rowHeight - 4,
                    InpColorNeutral, InpColorTextDim, ALIGN_LEFT, " Bal: $-- ", 8);
   
   currentY += rowHeight;
   
   // Daily Stats Row
   CreateEditObject(OBJ_DAILY, x + 2, currentY + 2, width - 4, rowHeight - 4,
                    InpColorNeutral, InpColorTextDim, ALIGN_LEFT, " Today: --W/--L | $-- ", 8);
   
   currentY += rowHeight;
   
   // Signal/Filter Status Row
   CreateEditObject(OBJ_SIGNAL, x + 2, currentY + 2, width - 4, rowHeight - 4,
                    InpColorNeutral, InpColorTextDim, ALIGN_LEFT, " Waiting... ", 8);
   
   currentY += rowHeight;
   
   // Position Info Box
   CreateEditObject(OBJ_POSITION, x + 2, currentY + 2, width - 4, (rowHeight * 2) - 2,
                    InpColorBg, InpColorTextDim, ALIGN_LEFT, " No Position ", 8);
}

void CreateEditObject(string name, int x, int y, int width, int height, 
                      color bgColor, color textColor, ENUM_ALIGN_MODE align, 
                      string text, int fontSize, bool bold = false)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, align);
   ObjectSetInteger(0, name, OBJPROP_READONLY, true);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   
   string fontName = bold ? "Arial Bold" : "Arial";
   ObjectSetString(0, name, OBJPROP_FONT, fontName);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

void UpdateProgressBar(double progress, color barColor)
{
   if(!InpEnableDashboard) return;
   
   int x = InpDashboardX;
   int y = InpDashboardY;
   int width = 280;
   int headerHeight = 28;
   int rowHeight = 22;
   int progressHeight = 4;
   
   // Calculate Y position (after header + 2 rows + countdown row)
   int progressY = y + headerHeight + (rowHeight * 3) + 2;
   
   int maxWidth = width - 4;
   int fillWidth = (int)(maxWidth * MathMax(0.0, MathMin(1.0, progress)));
   
   if(ObjectFind(0, OBJ_PROGRESS_BAR) >= 0)
   {
      ObjectSetInteger(0, OBJ_PROGRESS_BAR, OBJPROP_XSIZE, fillWidth);
      ObjectSetInteger(0, OBJ_PROGRESS_BAR, OBJPROP_BGCOLOR, barColor);
   }
   
   if(ObjectFind(0, OBJ_PROGRESS_BG) >= 0)
   {
      ObjectSetInteger(0, OBJ_PROGRESS_BG, OBJPROP_YDISTANCE, progressY);
   }
   if(ObjectFind(0, OBJ_PROGRESS_BAR) >= 0)
   {
      ObjectSetInteger(0, OBJ_PROGRESS_BAR, OBJPROP_YDISTANCE, progressY);
   }
}

void UpdateDashboard()
{
   if(!InpEnableDashboard) return;
   
   datetime now = TimeCurrent();
   if(now - g_LastStatusUpdate < InpStatusUpdateSec) return;
   g_LastStatusUpdate = now;
   
   // Update countdown trackers first
   int startupRemaining = 0;
   IsStartupDelayComplete(startupRemaining);
   
   int cooldownRemaining = 0;
   if(!IsCooldownComplete())
   {
      cooldownRemaining = g_CooldownRemaining;
   }
   
   UpdateSessionStatus();
   UpdateDailyStatistics();
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   // Determine current state and countdown
   string countdownText = "";
   color countdownColor = InpColorNeutral;
   color countdownTextColor = InpColorTextDim;
   double progress = 0.0;
   color progressColor = InpColorActive;
   bool showProgress = false;
   
   if(g_IsInStartup)
   {
      int mins = g_StartUpRemaining / 60;
      int secs = g_StartUpRemaining % 60;
      countdownText = " STARTUP: " + (mins > 0 ? IntegerToString(mins) + "m " : "") + IntegerToString(secs) + "s ";
      countdownColor = InpColorCountdown;
      countdownTextColor = InpColorText;
      progress = g_StartupProgress;
      progressColor = C'80, 100, 130'; // Blue-ish for startup
      showProgress = true;
   }
   else if(g_IsInCooldown)
   {
      int mins = g_CooldownRemaining / 60;
      int secs = g_CooldownRemaining % 60;
      countdownText = " COOLDOWN: " + (mins > 0 ? IntegerToString(mins) + "m " : "") + IntegerToString(secs) + "s ";
      countdownColor = InpColorWarning;
      countdownTextColor = C'40, 30, 10'; // Dark text on amber
      progress = g_CooldownProgress;
      progressColor = InpColorWarning;
      showProgress = true;
   }
   else
   {
      countdownText = " Ready to Trade ";
      countdownColor = InpColorActive;
      countdownTextColor = InpColorText;
      progress = 1.0;
      progressColor = InpColorActive;
      showProgress = false; // Hide progress when ready
   }
   
   // Update Countdown Row
   UpdateObject(OBJ_COUNTDOWN, countdownColor, countdownTextColor, countdownText);
   
   // Update Progress Bar
   if(showProgress)
   {
      UpdateProgressBar(progress, progressColor);
   }
   else
   {
      // Fill it completely when ready
      UpdateProgressBar(1.0, InpColorActive);
   }
   
   // Update Session Info
   color sessionColor = InpColorNeutral;
   string sessionText = " " + g_CurrentSession + " | " + g_SessionStatus;
   
   if(g_SessionStatus == "ACTIVE") sessionColor = InpColorNeutral;
   else if(g_SessionStatus == "STARTUP") sessionColor = InpColorCountdown;
   else if(g_SessionStatus == "COOLDOWN") sessionColor = InpColorWarning;
   else if(g_SessionStatus == "DISABLED") sessionColor = InpColorDisabled;
   else if(g_SessionStatus == "BUFFER" || g_SessionStatus == "HIGH-SPREAD") 
      sessionColor = InpColorWarning;
   
   UpdateObject(OBJ_SESSION, sessionColor, InpColorTextDim, sessionText);
   
   // Update Trading Status
   color tradingColor = g_IsTradingAllowed ? InpColorActive : InpColorDisabled;
   color tradingTextColor = InpColorText;
   string tradingText = "";
   
   if(g_IsTradingAllowed) 
   {
      tradingText = " ACTIVE ";
      tradingColor = InpColorActive;
   }
   else if(g_IsInStartup)
   {
      tradingText = " WARMUP ";
      tradingColor = InpColorCountdown;
   }
   else if(g_IsInCooldown)
   {
      tradingText = " PAUSE ";
      tradingColor = InpColorWarning;
   }
   else
   {
      tradingText = " STANDBY ";
      tradingColor = InpColorNeutral;
      tradingTextColor = InpColorTextDim;
   }
   
   UpdateObject(OBJ_TRADING, tradingColor, tradingTextColor, tradingText);
   
   // Update Price Info
   string priceText = " " + DoubleToString(bid, _Digits) + "  " + IntegerToString(spread) + " pts";
   color priceColor = InpColorNeutral;
   color priceTextColor = InpColorText;
   
   if(spread > InpMaxSpreadPoints * 0.8) priceTextColor = InpColorWarning;
   if(spread > InpMaxSpreadPoints) priceTextColor = InpColorDisabled;
   
   UpdateObject(OBJ_PRICE, priceColor, priceTextColor, priceText);
   
   // Update Account Info
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   string accountText = " Bal: $" + DoubleToString(balance, 2);
   
   if(MathAbs(equity - balance) > 0.01)
   {
      accountText += " (" + (equity > balance ? "+" : "") + DoubleToString(equity - balance, 2) + ")";
   }
   
   color accountColor = InpColorNeutral;
   color accountTextColor = InpColorText;
   
   if(equity > balance) accountTextColor = InpColorProfit;
   if(equity < balance) accountTextColor = InpColorLoss;
   
   UpdateObject(OBJ_ACCOUNT, accountColor, accountTextColor, accountText);
   
   // Update Daily Stats
   string dailyText = " " + IntegerToString(g_DailyWinCount) + "W / " + 
                      IntegerToString(g_DailyLossCount) + "L  |  $" + 
                      DoubleToString(g_DailyProfit, 2);
   
   color dailyColor = InpColorNeutral;
   color dailyTextColor = InpColorText;
   
   if(g_DailyProfit > 0) dailyTextColor = InpColorProfit;
   if(g_DailyProfit < 0) dailyTextColor = InpColorLoss;
   
   if((InpDailyMaxWinAmount > 0 && g_DailyProfit >= InpDailyMaxWinAmount * 0.8) || 
      (InpMaxTradesPerDay > 0 && g_DailyTradeCount >= InpMaxTradesPerDay * 0.8))
   {
      dailyTextColor = InpColorWarning;
   }
   
   UpdateObject(OBJ_DAILY, dailyColor, dailyTextColor, dailyText);
   
   // Update Signal/Filter Status
   string filterText = " ";
   color filterColor = InpColorNeutral;
   color filterTextColor = InpColorTextDim;
   
   if(g_IsInStartup)
   {
      filterText += "Initializing system...";
      filterTextColor = InpColorText;
   }
   else if(g_IsInCooldown)
   {
      filterText += "Waiting for cooldown...";
      filterTextColor = InpColorWarning;
   }
   else if(!g_IsTradingAllowed) 
   {
      filterText += "Session closed";
      filterTextColor = InpColorTextDim;
   }
   else if(!IsSpreadAcceptable()) 
   {
      filterText += "High spread detected";
      filterTextColor = InpColorWarning;
   }
   else if(!AreDailyLimitsOK()) 
   {
      filterText += "Daily limit reached";
      filterTextColor = InpColorDisabled;
   }
   else 
   {
      filterText += "Monitoring market...";
      filterTextColor = InpColorActive;
   }
   
   UpdateObject(OBJ_SIGNAL, filterColor, filterTextColor, filterText);
   
   // Update Position Info
   string posText = "";
   color posColor = InpColorBg;
   color posTextColor = InpColorTextDim;
   
   if(HasOpenPosition())
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double lots = PositionGetDouble(POSITION_VOLUME);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double currentPrice = (posType == POSITION_TYPE_BUY) ? bid : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profitPts = (posType == POSITION_TYPE_BUY) ? (currentPrice - entry)/_Point : (entry - currentPrice)/_Point;
         
         string typeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         
         posText += typeStr + " " + DoubleToString(lots, 2) + "  |  #" + IntegerToString((int)ticket) + "\n";
         posText += "$" + DoubleToString(profit, 2) + "  |  " + DoubleToString(profitPts, 0) + " pts";
         
         if(profitPts >= InpBreakevenTrigger) posText += "  BE";
         if(profitPts >= InpTrailingTrigger) posText += "  TRAIL";
         
         if(profit > 0) 
         {
            posColor = C'40, 55, 45';
            posTextColor = InpColorProfit;
         }
         else if(profit < 0) 
         {
            posColor = C'55, 40, 40';
            posTextColor = InpColorLoss;
         }
         else 
         {
            posColor = InpColorBg;
            posTextColor = InpColorText;
         }
         
         break;
      }
   }
   else
   {
      if(g_IsInCooldown)
      {
         posText = " Cooldown active\n Next trade in: " + IntegerToString(g_CooldownRemaining) + "s";
      }
      else if(g_IsInStartup)
      {
         posText = " System warming up\n Ready in: " + IntegerToString(g_StartUpRemaining) + "s";
      }
      else
      {
         posText = " No active position\n Signals: " + IntegerToString(g_SignalCheckCount);
      }
      posColor = InpColorBg;
      posTextColor = InpColorTextDim;
   }
   
   UpdateObject(OBJ_POSITION, posColor, posTextColor, posText);
}

void UpdateObject(string name, color bgColor, color textColor, string text)
{
   if(ObjectFind(0, name) >= 0)
   {
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
      ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }
}

void CleanupDashboard()
{
   ObjectsDeleteAll(0, OBJ_PREFIX);
   Comment("");
}

void UpdateDisplay()
{
   if(InpEnableDashboard)
      UpdateDashboard();
   else
      UpdateTextDisplay();
}

// Fallback text display with countdown
void UpdateTextDisplay()
{
   if(!InpShowSessionInfo && !InpShowPositionInfo) return;
   
   datetime now = TimeCurrent();
   if(now - g_LastStatusUpdate < InpStatusUpdateSec) return;
   g_LastStatusUpdate = now;
   
   // Update countdown trackers
   int startupRemaining = 0;
   IsStartupDelayComplete(startupRemaining);
   
   if(!IsCooldownComplete())
   {
      // Already updated in function
   }
   
   UpdateSessionStatus();
   
   string display = "";
   display += "----------------------------------------\n";
   display += InpStrategyName + "  |  " + g_CurrentSession + "\n";
   display += "----------------------------------------\n";
   
   // Countdown priority
   if(g_IsInStartup)
   {
      int mins = g_StartUpRemaining / 60;
      int secs = g_StartUpRemaining % 60;
      display += ">> STARTUP: " + (mins > 0 ? IntegerToString(mins) + "m " : "") + IntegerToString(secs) + "s remaining\n";
      display += "----------------------------------------\n";
   }
   else if(g_IsInCooldown)
   {
      int mins = g_CooldownRemaining / 60;
      int secs = g_CooldownRemaining % 60;
      display += ">> COOLDOWN: " + (mins > 0 ? IntegerToString(mins) + "m " : "") + IntegerToString(secs) + "s remaining\n";
      display += "----------------------------------------\n";
   }
   
   display += "Status: " + g_SessionStatus + "  |  Trading: " + (g_IsTradingAllowed ? "ON" : "OFF") + "\n";
   
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   display += "Price: " + DoubleToString(bid, _Digits) + "  Spread: " + IntegerToString(spread) + "\n";
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   display += "Balance: $" + DoubleToString(balance, 2) + "  Equity: $" + DoubleToString(equity, 2) + "\n";
   
   UpdateDailyStatistics();
   display += "Today: " + IntegerToString(g_DailyWinCount) + "W/" + 
              IntegerToString(g_DailyLossCount) + "L  P&L: $" + DoubleToString(g_DailyProfit, 2) + "\n";
   
   bool hasPosition = HasOpenPosition();
   if(hasPosition)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double lots = PositionGetDouble(POSITION_VOLUME);
         double profit = PositionGetDouble(POSITION_PROFIT);
         
         display += "Pos: " + (posType == POSITION_TYPE_BUY ? "BUY" : "SELL") + " " + 
                    DoubleToString(lots, 2) + "  P&L: $" + DoubleToString(profit, 2) + "\n";
      }
   }
   else
   {
      display += "No position | Checks: " + IntegerToString(g_SignalCheckCount) + "\n";
   }
   
   display += "----------------------------------------";
   
   Comment(display);
}

//+------------------------------------------------------------------+
//| EVENT HANDLERS                                                   |
//+------------------------------------------------------------------+

int OnInit()
{
   if(!IsSymbolGold(_Symbol))
   {
      Print("[ERROR] This EA is for XAUUSD/GOLD only. Current symbol: ", _Symbol);
      return(INIT_FAILED);
   }

   // Create indicators
   g_HandleFastMA = iMA(_Symbol, InpTimeframe, InpFastMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_HandleSlowMA = iMA(_Symbol, InpTimeframe, InpSlowMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_HandleRSI = iRSI(_Symbol, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   g_HandleATR = iATR(_Symbol, InpTimeframe, InpATRPeriod);
   g_HandleMomentum = iMomentum(_Symbol, InpTimeframe, InpMomentumPeriod, PRICE_CLOSE);
   g_HandleADX = iADX(_Symbol, InpTimeframe, InpADXPeriod);

   if(g_HandleFastMA == INVALID_HANDLE || g_HandleSlowMA == INVALID_HANDLE ||
      g_HandleRSI == INVALID_HANDLE || g_HandleATR == INVALID_HANDLE)
   {
      Print("[ERROR] Failed to create essential indicators");
      return(INIT_FAILED);
   }

   TradeManager.SetExpertMagicNumber(InpMagicNumber);

   // Initialize globals
   g_EAStartTime = TimeCurrent();
   g_LastBarTime = 0;
   g_LastTradeTime = 0;
   g_LastStatusUpdate = 0;
   g_CurrentDayOfYear = GetDayOfYear();
   g_DailyTradeCount = 0;
   g_DailyWinCount = 0;
   g_DailyLossCount = 0;
   g_SignalCheckCount = 0;
   g_IsInStartup = false;
   g_IsInCooldown = false;

   // Create Dashboard Objects
   CreateDashboardObjects();

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Print initialization info
   Print("========================================");
   Print("   ", InpStrategyName, " v5.10 INITIALIZED");
   Print("========================================");
   Print("Account Balance: $", DoubleToString(balance, 2));
   Print("Base Lot Size: ", InpBaseLotSize, " (Max: ", InpMaxLotSize, ")");
   Print("Stop Loss: ", InpStopLossPoints, " points");
   Print("Take Profit: ", InpTakeProfitPoints, " points");
   Print("Max Spread: ", InpMaxSpreadPoints, " points");
   if(InpStartupDelaySec > 0)
      Print("Startup Delay: ", InpStartupDelaySec, " seconds");
   else
      Print("Startup Delay: DISABLED");
   Print("Dashboard: ", InpEnableDashboard ? "ENABLED (Countdown)" : "DISABLED");
   Print("========================================");

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   // Release indicators
   if(g_HandleFastMA != INVALID_HANDLE) IndicatorRelease(g_HandleFastMA);
   if(g_HandleSlowMA != INVALID_HANDLE) IndicatorRelease(g_HandleSlowMA);
   if(g_HandleRSI != INVALID_HANDLE) IndicatorRelease(g_HandleRSI);
   if(g_HandleATR != INVALID_HANDLE) IndicatorRelease(g_HandleATR);
   if(g_HandleMomentum != INVALID_HANDLE) IndicatorRelease(g_HandleMomentum);
   if(g_HandleADX != INVALID_HANDLE) IndicatorRelease(g_HandleADX);

   UpdateDailyStatistics();
   CleanupDashboard();
   
   Print(InpStrategyName, " deinitialized");
   Print("Final Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
}

void OnTick()
{
   if(!IsSymbolGold(_Symbol)) return;

   // Always update display (for countdowns)
   UpdateDisplay();

   // Manage existing positions
   ManageOpenPositions();

   // Check for new bar
   if(!IsNewBar()) return;

   // Check spread
   int currentSpread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(!IsSpreadAcceptable())
   {
      if(InpLogSignalDetails && (g_SignalCheckCount % 20 == 0))
         LogMessage("[FILTER] Spread too high: " + IntegerToString(currentSpread));
      return;
   }

   // Check startup delay
   int startupRemaining = 0;
   if(!IsStartupDelayComplete(startupRemaining))
   {
      if(InpLogSignalDetails && (g_SignalCheckCount % 10 == 0))
         LogMessage("[WAIT] Startup delay: " + IntegerToString(startupRemaining) + "s remaining");
      return;
   }

   // Check session
   if(!IsTradingSessionOK()) return;

   // Check cooldown
   if(!IsCooldownComplete())
   {
      int remaining = InpTradeCooldownSec - (int)(TimeCurrent() - g_LastTradeTime);
      if(remaining > 0 && (g_SignalCheckCount % 10 == 0))
         LogMessage("[WAIT] Cooldown: " + IntegerToString(remaining) + "s");
      return;
   }

   // Check daily limits
   if(!AreDailyLimitsOK()) return;

   // Check if position already open
   if(InpOneTradeAtATime && HasOpenPosition()) return;

   // Check signals
   bool buySignal = CheckBuySignal();
   bool sellSignal = CheckSellSignal();

   if(buySignal && sellSignal)
   {
      LogMessage("[FILTER] Conflicting signals - skipping");
      return;
   }

   if(buySignal) ExecuteTrade(true);
   if(sellSignal) ExecuteTrade(false);
}
//+------------------------------------------------------------------+