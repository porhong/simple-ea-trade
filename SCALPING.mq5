//+------------------------------------------------------------------+
//|                                                   SCALPING.mq5    |
//|                        MT5 Expert Advisor for XAUUSD (Scalping)   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.02"
#property description "XAUUSD Scalping EA: EMA+RSI+ATR, spread/session filters, risk mgmt, cooldown, trailing, breakeven."
#property description "Trades only XAUUSD."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo pos;

//----------------------------
// Inputs (Configurable Params)
//----------------------------
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M5;     // Working timeframe
input long            InpMagic            = 20260209;      // Magic number
input bool            InpOnePositionOnly  = true;          // Only one open position at a time

// Risk / Size
input bool   InpUseRiskPercent     = false;   // If true, use risk % sizing (else fixed lots)
input double InpRiskPercent        = 1.0;     // Risk % per trade (if enabled)
input double InpFixedLot           = 0.01;    // Fixed lot size (if risk% disabled)
input double InpMaxLot             = 2.0;     // Hard cap lots (safety)
input double InpMinLot             = 0.01;    // Min lots (safety)

// Stops / Targets
input bool   InpUseATRStops        = true;    // ATR-based SL/TP (recommended for XAU)
input int    InpATRPeriod          = 14;      // ATR period
input double InpATR_SL_Mult        = 1.3;     // SL = ATR * mult
input double InpATR_TP_Mult        = 1.3;     // TP = ATR * mult (>= SL for better R:R)
input int    InpFixedSL_Points     = 600;     // Fixed SL in points (if ATR disabled)
input int    InpFixedTP_Points     = 450;     // Fixed TP in points (if ATR disabled)

// Spread / Slippage
input int    InpMaxSpreadPoints    = 120;     // Maximum spread allowed (points, tight for scalping)
input int    InpDeviationPoints    = 30;      // Max price deviation (points)
input bool   InpUseMaxSpreadPctATR = false;   // Skip if spread > X% of ATR
input double InpMaxSpreadPctATR   = 30.0;    // Max spread as % of ATR (points)
input bool   InpUseSpreadVsTarget = true;     // Skip if spread > X% of TP distance
input double InpMaxSpreadPctTarget = 40.0;    // Max spread as % of TP (e.g. 40 = 40%)

// Entry Indicators
input int    InpFastEMA            = 9;       // Fast EMA
input int    InpSlowEMA            = 21;      // Slow EMA
input int    InpRSIPeriod          = 14;      // RSI period
input double InpRSI_BuyAbove       = 55.0;    // Buy only if RSI >= this (stronger filter)
input double InpRSI_SellBelow      = 45.0;    // Sell only if RSI <= this (stronger filter)

// Overtrading Protection
input int    InpCooldownSeconds    = 180;     // Cooldown between new trades (seconds)
input int    InpMaxTradesPerDay    = 12;      // Max trades per day (EA+symbol+magic)

// Session Filter (optional)
input bool   InpUseSessionFilter   = false;   // Enable session filter
input int    InpTradeStartHour     = 7;       // Start hour (server time)
input int    InpTradeEndHour       = 20;      // End hour (server time)

// "News" Avoidance (manual windows)
input bool   InpUseNewsWindows     = false;   // Enable manual news windows
input int    InpNewsBufferMinutes  = 30;      // Avoid trading +/- buffer minutes
input string InpNewsTimes          = "";      // "YYYY.MM.DD HH:MI;YYYY.MM.DD HH:MI;..."

// Trade Management
input bool   InpUseBreakeven       = true;
input int    InpBreakevenTrigger   = 250;
input int    InpBreakevenOffset    = 30;

input bool   InpUseTrailingStop    = true;
input int    InpTrailStart         = 300;
input int    InpTrailDistance      = 220;

// Volatility Guard
input bool   InpUseATRVolGuard     = true;
input double InpMaxATRPoints       = 1200;

// Trend Filter (higher timeframe)
input bool   InpUseTrendFilter     = false;   // Trade only with H1 trend
input ENUM_TIMEFRAMES InpTrendTimeframe = PERIOD_H1;
input int    InpTrendEMAPeriod     = 50;      // H1 EMA period

// Debug
input bool   InpEnableDebugLog     = true;    // Print debug messages to Experts tab

//----------------------------
// Globals / Handles
//----------------------------
int    hFastEma   = INVALID_HANDLE;
int    hSlowEma   = INVALID_HANDLE;
int    hRsi       = INVALID_HANDLE;
int    hAtr       = INVALID_HANDLE;
int    hTrendEma  = INVALID_HANDLE;

datetime g_lastBarTime = 0;
datetime g_lastTradeTime = 0;

int     g_tradesToday = 0;
int     g_todayDoy = -1;

//----------------------------
// Helpers
//----------------------------
void DebugLog(string msg)
{
   if(InpEnableDebugLog) Print("[SCALPING] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " | ", msg);
}

string TrimStr(string s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
   return s;
}

bool IsXAUUSD(const string sym)
{
   // Enforce "XAUUSD" substring. Adjust if your broker uses GOLD or XAUUSDm.
   return (StringFind(sym, "XAUUSD") >= 0);
}

int CurrentDoy()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);

   MqlDateTime jan1 = tm;
   jan1.mon=1; jan1.day=1; jan1.hour=0; jan1.min=0; jan1.sec=0;
   datetime tJan1 = StructToTime(jan1);

   int doy = (int)((TimeCurrent() - tJan1) / 86400);
   return doy;
}

void ResetDailyCountersIfNeeded()
{
   int doy = CurrentDoy();
   if(doy != g_todayDoy)
   {
      g_todayDoy = doy;
      g_tradesToday = 0;
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

bool TradingHoursOK()
{
   if(!InpUseSessionFilter) return true;

   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   int h = tm.hour;

   if(InpTradeStartHour <= InpTradeEndHour)
      return (h >= InpTradeStartHour && h < InpTradeEndHour);
   else
      return (h >= InpTradeStartHour || h < InpTradeEndHour);
}

bool CooldownOK()
{
   if(InpCooldownSeconds <= 0) return true;
   return (TimeCurrent() - g_lastTradeTime) >= InpCooldownSeconds;
}

bool TradesPerDayOK()
{
   ResetDailyCountersIfNeeded();
   return (InpMaxTradesPerDay <= 0) ? true : (g_tradesToday < InpMaxTradesPerDay);
}

bool ParseDateTime(const string s, datetime &out)
{
   out = StringToTime(s);
   return (out > 0);
}

bool IsInNewsWindow()
{
   if(!InpUseNewsWindows) return false;
   if(StringLen(InpNewsTimes) < 5) return false;

   string items[];
   int n = StringSplit(InpNewsTimes, ';', items);
   if(n <= 0) return false;

   datetime now = TimeCurrent();
   int bufferSec = InpNewsBufferMinutes * 60;

   for(int i=0;i<n;i++)
   {
      string t = TrimStr(items[i]);
      if(StringLen(t) < 10) continue;

      datetime ev;
      if(!ParseDateTime(t, ev)) continue;

      if(MathAbs((long)(now - ev)) <= bufferSec)
         return true;
   }
   return false;
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

double CalcLotsByRisk(int slPoints)
{
   if(slPoints <= 0) return NormalizeVolume(InpFixedLot);

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);

   double tickSize=0, tickValue=0;
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE, tickSize);
   SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE, tickValue);

   if(tickSize <= 0 || tickValue <= 0)
      return NormalizeVolume(InpFixedLot);

   double pointValuePerLot = tickValue * (_Point / tickSize);
   if(pointValuePerLot <= 0)
      return NormalizeVolume(InpFixedLot);

   double lossPerLot = slPoints * pointValuePerLot;
   if(lossPerLot <= 0)
      return NormalizeVolume(InpFixedLot);

   double lots = riskMoney / lossPerLot;
   return NormalizeVolume(lots);
}

bool GetIndicatorValues(double &fastEma1, double &slowEma1, double &rsi1, double &atr1)
{
   double bFast[3], bSlow[3], bRsi[3], bAtr[3];

   if(CopyBuffer(hFastEma, 0, 0, 3, bFast) < 3) return false;
   if(CopyBuffer(hSlowEma, 0, 0, 3, bSlow) < 3) return false;
   if(CopyBuffer(hRsi,     0, 0, 3, bRsi)  < 3) return false;
   if(CopyBuffer(hAtr,     0, 0, 3, bAtr)  < 3) return false;

   fastEma1 = bFast[1];
   slowEma1 = bSlow[1];
   rsi1     = bRsi[1];
   atr1     = bAtr[1];

   return true;
}

bool TrendFilterAllowsBuy()
{
   if(!InpUseTrendFilter || hTrendEma == INVALID_HANDLE) return true;
   double buf[1];
   if(CopyBuffer(hTrendEma, 0, 1, 1, buf) < 1) return true;
   double trendEma = buf[0];
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   return (price > trendEma);
}

bool TrendFilterAllowsSell()
{
   if(!InpUseTrendFilter || hTrendEma == INVALID_HANDLE) return true;
   double buf[1];
   if(CopyBuffer(hTrendEma, 0, 1, 1, buf) < 1) return true;
   double trendEma = buf[0];
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return (price < trendEma);
}

void ComputeStopsInPoints(double atrValue, int &slPts, int &tpPts)
{
   if(InpUseATRStops)
   {
      double atrPts = atrValue / _Point;
      slPts = (int)MathRound(atrPts * InpATR_SL_Mult);
      tpPts = (int)MathRound(atrPts * InpATR_TP_Mult);

      slPts = MathMax(slPts, 250);
      tpPts = MathMax(tpPts, 150);
   }
   else
   {
      slPts = MathMax(InpFixedSL_Points, 50);
      tpPts = MathMax(InpFixedTP_Points, 50);
   }
}

bool CheckBuySignal()
{
   double fe,se,rs,at;
   if(!GetIndicatorValues(fe,se,rs,at)) return false;

   double f[3], s[3];
   if(CopyBuffer(hFastEma, 0, 0, 3, f) < 3) return false;
   if(CopyBuffer(hSlowEma, 0, 0, 3, s) < 3) return false;

   bool crossUp = (f[2] <= s[2]) && (f[1] > s[1]);
   if(!crossUp) return false;

   if(rs < InpRSI_BuyAbove) return false;
   if(!TrendFilterAllowsBuy()) return false;

   if(InpUseATRVolGuard)
   {
      double atrPts = at / _Point;
      if(atrPts > InpMaxATRPoints) return false;
   }
   return true;
}

bool CheckSellSignal()
{
   double fe,se,rs,at;
   if(!GetIndicatorValues(fe,se,rs,at)) return false;

   double f[3], s[3];
   if(CopyBuffer(hFastEma, 0, 0, 3, f) < 3) return false;
   if(CopyBuffer(hSlowEma, 0, 0, 3, s) < 3) return false;

   bool crossDown = (f[2] >= s[2]) && (f[1] < s[1]);
   if(!crossDown) return false;

   if(rs > InpRSI_SellBelow) return false;
   if(!TrendFilterAllowsSell()) return false;

   if(InpUseATRVolGuard)
   {
      double atrPts = at / _Point;
      if(atrPts > InpMaxATRPoints) return false;
   }
   return true;
}

bool OpenTrade(bool isBuy)
{
   double atr1;
   {
      double fe,se,rs;
      if(!GetIndicatorValues(fe,se,rs,atr1)) return false;
   }

   int slPts=0, tpPts=0;
   ComputeStopsInPoints(atr1, slPts, tpPts);

   int spreadPoints = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpUseMaxSpreadPctATR && spreadPoints > 0)
   {
      double atrPts = atr1 / _Point;
      if(atrPts > 0)
      {
         double spreadPctATR = (double)spreadPoints / atrPts * 100.0;
         if(spreadPctATR > InpMaxSpreadPctATR)
         {
            DebugLog("OpenTrade SKIP: spread " + DoubleToString(spreadPctATR, 1) + "% of ATR > max " + DoubleToString(InpMaxSpreadPctATR, 1) + "%");
            return false;
         }
      }
   }
   if(InpUseSpreadVsTarget && spreadPoints > 0 && tpPts > 0)
   {
      double spreadPctTarget = (double)spreadPoints / (double)tpPts * 100.0;
      if(spreadPctTarget > InpMaxSpreadPctTarget)
      {
         DebugLog("OpenTrade SKIP: spread " + DoubleToString(spreadPctTarget, 1) + "% of TP > max " + DoubleToString(InpMaxSpreadPctTarget, 1) + "%");
         return false;
      }
   }

   double lots = InpUseRiskPercent ? CalcLotsByRisk(slPts) : NormalizeVolume(InpFixedLot);
   if(lots <= 0)
   {
      DebugLog("OpenTrade SKIP: lots=0");
      return false;
   }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = isBuy ? ask : bid;

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
   DebugLog("OpenTrade ATTEMPT " + side + " lots=" + DoubleToString(lots, 2) + " entry=" + DoubleToString(entry, _Digits) +
      " SL=" + DoubleToString(sl, _Digits) + " TP=" + DoubleToString(tp, _Digits) + " (SLpts=" + IntegerToString(slPts) + " TPpts=" + IntegerToString(tpPts) + ")");

   bool ok = false;
   if(isBuy) ok = trade.Buy(lots, _Symbol, entry, sl, tp, "XAU Scalper BUY");
   else      ok = trade.Sell(lots, _Symbol, entry, sl, tp, "XAU Scalper SELL");

   if(ok)
   {
      g_lastTradeTime = TimeCurrent();
      ResetDailyCountersIfNeeded();
      g_tradesToday++;
      DebugLog("OpenTrade OK " + side + " ticket=" + IntegerToString(trade.ResultOrder()) + " tradesToday=" + IntegerToString(g_tradesToday));
   }
   else
      DebugLog("OpenTrade FAIL " + side + " retcode=" + IntegerToString(trade.ResultRetcode()) + " " + trade.ResultRetcodeDescription());
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
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl     = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double price = (type == POSITION_TYPE_BUY) ? bid : ask;

      double profitPts = 0;
      if(type == POSITION_TYPE_BUY)  profitPts = (price - entry) / _Point;
      if(type == POSITION_TYPE_SELL) profitPts = (entry - price) / _Point;

      double newSL = sl;

      // Breakeven
      if(InpUseBreakeven && profitPts >= InpBreakevenTrigger)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double be = entry + InpBreakevenOffset * _Point;
            if(sl < be || sl == 0.0) newSL = be;
         }
         else
         {
            double be = entry - InpBreakevenOffset * _Point;
            if(sl > be || sl == 0.0) newSL = be;
         }
      }

      // Trailing
      if(InpUseTrailingStop && profitPts >= InpTrailStart)
      {
         if(type == POSITION_TYPE_BUY)
         {
            double trailSL = price - InpTrailDistance * _Point;
            if(trailSL > newSL) newSL = trailSL;
         }
         else
         {
            double trailSL = price + InpTrailDistance * _Point;
            if(trailSL < newSL || newSL == 0.0) newSL = trailSL;
         }
      }

      if(newSL != sl)
      {
         trade.SetExpertMagicNumber(InpMagic);
         bool modOk = trade.PositionModify(ticket, newSL, tp);
         if(modOk)
            DebugLog("ManagePosition MODIFY ticket=" + IntegerToString((int)ticket) + " newSL=" + DoubleToString(newSL, _Digits) +
               " (BE=" + (InpUseBreakeven && profitPts >= InpBreakevenTrigger ? "1" : "0") +
               " Trail=" + (InpUseTrailingStop && profitPts >= InpTrailStart ? "1" : "0") + " profitPts=" + DoubleToString(profitPts, 0) + ")");
         else
            DebugLog("ManagePosition MODIFY FAIL ticket=" + IntegerToString((int)ticket) + " retcode=" + IntegerToString(trade.ResultRetcode()));
      }
   }
}

//----------------------------
// MT5 Standard Event Handlers
//----------------------------
int OnInit()
{
   if(!IsXAUUSD(_Symbol))
   {
      Print("This EA is designed to trade XAUUSD only. Current symbol: ", _Symbol);
      return(INIT_FAILED);
   }

   hFastEma = iMA(_Symbol, InpTimeframe, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hSlowEma = iMA(_Symbol, InpTimeframe, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hRsi     = iRSI(_Symbol, InpTimeframe, InpRSIPeriod, PRICE_CLOSE);
   hAtr     = iATR(_Symbol, InpTimeframe, InpATRPeriod);

   if(InpUseTrendFilter)
   {
      hTrendEma = iMA(_Symbol, InpTrendTimeframe, InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(hTrendEma == INVALID_HANDLE)
      {
         Print("Failed to create trend EMA handle.");
         return(INIT_FAILED);
      }
   }

   if(hFastEma == INVALID_HANDLE || hSlowEma == INVALID_HANDLE ||
      hRsi == INVALID_HANDLE || hAtr == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(InpMagic);

   g_lastBarTime = 0;
   g_lastTradeTime = 0;
   g_todayDoy = CurrentDoy();
   g_tradesToday = 0;

   Print("XAU Scalper EA initialized. Timeframe=", EnumToString(InpTimeframe), " Magic=", InpMagic);
   if(InpEnableDebugLog) DebugLog("Debug logging ON. Filters: SpreadMax=" + IntegerToString(InpMaxSpreadPoints) +
      " Cooldown=" + IntegerToString(InpCooldownSeconds) + "s MaxTradesDay=" + IntegerToString(InpMaxTradesPerDay));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(hFastEma != INVALID_HANDLE) IndicatorRelease(hFastEma);
   if(hSlowEma != INVALID_HANDLE) IndicatorRelease(hSlowEma);
   if(hRsi     != INVALID_HANDLE) IndicatorRelease(hRsi);
   if(hAtr     != INVALID_HANDLE) IndicatorRelease(hAtr);
   if(hTrendEma != INVALID_HANDLE) IndicatorRelease(hTrendEma);

   Print("XAU Scalper EA deinitialized. Reason=", reason);
}

void OnTick()
{
   if(!IsXAUUSD(_Symbol)) return;

   ManagePosition();

   if(!IsNewBar()) return;

   int spreadPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(!SpreadOK())
   {
      DebugLog("NewBar SKIP: spread=" + IntegerToString(spreadPts) + " > max " + IntegerToString(InpMaxSpreadPoints));
      return;
   }
   if(!TradingHoursOK())
   {
      DebugLog("NewBar SKIP: outside session hours");
      return;
   }
   if(IsInNewsWindow())
   {
      DebugLog("NewBar SKIP: inside news window");
      return;
   }
   if(!CooldownOK())
   {
      DebugLog("NewBar SKIP: cooldown active");
      return;
   }
   if(!TradesPerDayOK())
   {
      DebugLog("NewBar SKIP: max trades/day reached (" + IntegerToString(g_tradesToday) + "/" + IntegerToString(InpMaxTradesPerDay) + ")");
      return;
   }

   if(InpOnePositionOnly && HasOpenPosition())
   {
      DebugLog("NewBar SKIP: already have position (one at a time)");
      return;
   }

   bool buySignal  = CheckBuySignal();
   bool sellSignal = CheckSellSignal();

   if(buySignal && sellSignal)
   {
      DebugLog("NewBar SKIP: conflicting signals (buy and sell)");
      return;
   }

   if(buySignal)  OpenTrade(true);
   if(sellSignal) OpenTrade(false);

   if(!buySignal && !sellSignal)
      DebugLog("NewBar: no signal (spread=" + IntegerToString(spreadPts) + ")");
}
//+------------------------------------------------------------------+
