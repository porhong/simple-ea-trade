//+------------------------------------------------------------------+
//|                                           SCALPING_LOWBUDGET.mq5 |
//|                    Low Budget High Win-Rate Scalper for XAUUSD   |
//+------------------------------------------------------------------+
#property strict
#property version   "2.10"
#property description "XAUUSD Low-Budget Scalper: Small profits, high win rate, conservative"
#property description "Optimized for accounts under $500. Tight stops, quick profits."

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>

CTrade        trade;
CPositionInfo pos;

//----------------------------
// Inputs
//----------------------------
input ENUM_TIMEFRAMES InpTimeframe        = PERIOD_M5;
input long            InpMagic            = 20260210;
input bool            InpOnePositionOnly  = true;

// Risk Management (Small Account Optimized)
input double InpFixedLot           = 0.01;    // Start VERY small
input double InpMaxLot             = 0.05;    // Cap at 0.05 for safety
input double InpMinLot             = 0.01;
input int    InpMaxDailyLoss       = 5;       // Stop after X losing trades per day
input int    InpMaxDailyProfit     = 20;      // Take profit after X winning trades

// Scalping Stops/Targets (TIGHT for quick profits)
input int    InpScalpSL_Points     = 150;     // Very tight SL (15 pips on XAU ~$1.50)
input int    InpScalpTP_Points     = 200;     // Quick TP (20 pips ~$2.00)
input bool   InpUsePartialTP       = true;    // Close 50% at TP1
input int    InpPartialTP_Points   = 120;     // Partial TP (12 pips ~$1.20)
input double InpPartialClosePercent = 50.0;   // Close 50% of position

// Spread Filter (CRITICAL for scalping)
input int    InpMaxSpreadPoints    = 80;      // Very tight - only trade low spread
input int    InpDeviationPoints    = 20;

// Entry Filters (CONSERVATIVE for high win rate)
input int    InpFastEMA            = 9;
input int    InpSlowEMA            = 21;
input int    InpRSIPeriod          = 14;
input int    InpATRPeriod          = 14;

// Win Rate Optimization Filters
input bool   InpRequireStrongMomentum = true;   // Must have momentum
input int    InpMomentumPeriod        = 10;
input double InpMinMomentumThreshold  = 0.0003; // Strong momentum only

input bool   InpRequireTrendAlignment = true;   // Price must align with EMA trend
input bool   InpAvoidChoppyMarket     = true;   // Skip if ADX < threshold
input int    InpADXPeriod             = 14;
input double InpMinADX                = 20.0;   // Minimum trend strength

input bool   InpRequireRSIConfirmation = true;  // Strict RSI zones
input double InpRSI_BuyMin            = 45.0;   // Buy: RSI 45-65
input double InpRSI_BuyMax            = 65.0;
input double InpRSI_SellMin           = 35.0;   // Sell: RSI 35-55
input double InpRSI_SellMax           = 55.0;

input bool   InpRequirePriceAction    = true;   // Candle pattern confirmation
input double InpMinCandleBodyPercent  = 40.0;   // Candle body must be 40%+ of range

// Overtrading Protection
input int    InpCooldownSeconds    = 300;      // 5 min cooldown (avoid revenge trading)
input int    InpMaxTradesPerDay    = 15;       // Conservative limit

// Session Filter (IMPORTANT for spreads)
input bool   InpUseSessionFilter   = true;
input int    InpTradeStartHour     = 8;        // London open
input int    InpTradeEndHour       = 17;       // Before NY close

// Quick Trade Management (Scalping Style)
input bool   InpUseQuickBreakeven  = true;
input int    InpBE_Trigger         = 80;       // Move to BE at 8 pips
input int    InpBE_Offset          = 10;       // +1 pip profit lock

input bool   InpUseTrailingStop    = true;
input int    InpTrail_Start        = 120;      // Start trailing at 12 pips
input int    InpTrail_Distance     = 50;       // Trail 5 pips behind

// Market Condition Filters
input bool   InpAvoidHighVolatility = true;
input double InpMaxATRPoints        = 800;     // Skip if too volatile
input bool   InpAvoidLowVolatility  = true;
input double InpMinATRPoints        = 200;     // Skip if too quiet

// Debug
input bool   InpEnableDebugLog     = true;
input bool   InpLogSessionStatus   = false;     // Less spam
input bool   InpLogSignalAnalysis  = true;
input bool   InpShowDailyStats     = true;

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

int     g_tradesToday = 0;
int     g_winsToday = 0;
int     g_lossesToday = 0;
int     g_todayDoy = -1;
double  g_profitToday = 0.0;

//----------------------------
// Helpers
//----------------------------
void DebugLog(string msg)
{
   if(InpEnableDebugLog) Print("[LOW-BUDGET] ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), " | ", msg);
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

void ResetDailyCountersIfNeeded()
{
   int doy = CurrentDoy();
   if(doy != g_todayDoy)
   {
      if(g_todayDoy != -1 && InpShowDailyStats)
      {
         DebugLog("=== DAILY STATS ===");
         DebugLog("Total Trades: " + IntegerToString(g_tradesToday));
         DebugLog("Wins: " + IntegerToString(g_winsToday) + " | Losses: " + IntegerToString(g_lossesToday));
         if(g_tradesToday > 0)
         {
            double winRate = (double)g_winsToday / (double)g_tradesToday * 100.0;
            DebugLog("Win Rate: " + DoubleToString(winRate, 1) + "%");
         }
         DebugLog("Profit: $" + DoubleToString(g_profitToday, 2));
         DebugLog("==================");
      }
      
      g_todayDoy = doy;
      g_tradesToday = 0;
      g_winsToday = 0;
      g_lossesToday = 0;
      g_profitToday = 0.0;
   }
}

void UpdateDailyStats()
{
   ResetDailyCountersIfNeeded();
   
   // Count closed positions from today
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
      g_profitToday += profit;
      
      if(profit > 0) g_winsToday++;
      else if(profit < 0) g_lossesToday++;
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

bool DailyLimitsOK()
{
   ResetDailyCountersIfNeeded();
   UpdateDailyStats();
   
   // Check max trades
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
   {
      DebugLog("Daily trade limit reached (" + IntegerToString(g_tradesToday) + "/" + IntegerToString(InpMaxTradesPerDay) + ")");
      return false;
   }
   
   // Check max losses
   if(InpMaxDailyLoss > 0 && g_lossesToday >= InpMaxDailyLoss)
   {
      DebugLog("Daily loss limit reached (" + IntegerToString(g_lossesToday) + " losses)");
      return false;
   }
   
   // Check max wins (take profit for the day)
   if(InpMaxDailyProfit > 0 && g_winsToday >= InpMaxDailyProfit)
   {
      DebugLog("Daily profit target reached (" + IntegerToString(g_winsToday) + " wins) - DONE FOR THE DAY!");
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
   
   // Check last completed candle
   double open = rates[0].open;
   double close = rates[0].close;
   double high = rates[0].high;
   double low = rates[0].low;
   
   double range = high - low;
   if(range <= 0) return false;
   
   double body = MathAbs(close - open);
   double bodyPercent = (body / range) * 100.0;
   
   // Require strong body (not doji)
   if(bodyPercent < InpMinCandleBodyPercent)
   {
      if(InpLogSignalAnalysis)
         DebugLog("Candle pattern REJECT: Weak body " + DoubleToString(bodyPercent, 1) + "% < " + DoubleToString(InpMinCandleBodyPercent, 1) + "%");
      return false;
   }
   
   // Check direction matches
   if(isBuy && close <= open)
   {
      if(InpLogSignalAnalysis)
         DebugLog("Candle pattern REJECT: BUY signal but bearish candle");
      return false;
   }
   
   if(!isBuy && close >= open)
   {
      if(InpLogSignalAnalysis)
         DebugLog("Candle pattern REJECT: SELL signal but bullish candle");
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

   string rejectReason = "";

   // ATR Volatility Check
   double atrPts = at / _Point;
   if(InpAvoidHighVolatility && atrPts > InpMaxATRPoints)
   {
      rejectReason = "High volatility (ATR=" + DoubleToString(atrPts, 0) + " > " + DoubleToString(InpMaxATRPoints, 0) + ")";
      if(InpLogSignalAnalysis) DebugLog("BUY REJECT: " + rejectReason);
      return false;
   }
   if(InpAvoidLowVolatility && atrPts < InpMinATRPoints)
   {
      rejectReason = "Low volatility (ATR=" + DoubleToString(atrPts, 0) + " < " + DoubleToString(InpMinATRPoints, 0) + ")";
      if(InpLogSignalAnalysis) DebugLog("BUY REJECT: " + rejectReason);
      return false;
   }

   // ADX Trend Strength
   if(InpAvoidChoppyMarket && adx < InpMinADX)
   {
      rejectReason = "Choppy market (ADX=" + DoubleToString(adx, 1) + " < " + DoubleToString(InpMinADX, 1) + ")";
      if(InpLogSignalAnalysis) DebugLog("BUY REJECT: " + rejectReason);
      return false;
   }

   // EMA must be in bullish alignment
   if(InpRequireTrendAlignment && fast[1] <= slow[1])
   {
      rejectReason = "No trend alignment (Fast <= Slow)";
      if(InpLogSignalAnalysis) DebugLog("BUY REJECT: " + rejectReason);
      return false;
   }

   // Momentum confirmation
   if(InpRequireStrongMomentum && mom < InpMinMomentumThreshold)
   {
      rejectReason = "Weak momentum (" + DoubleToString(mom, 5) + " < " + DoubleToString(InpMinMomentumThreshold, 5) + ")";
      if(InpLogSignalAnalysis) DebugLog("BUY REJECT: " + rejectReason);
      return false;
   }

   // RSI must be in safe buy zone
   if(InpRequireRSIConfirmation)
   {
      if(rs < InpRSI_BuyMin || rs > InpRSI_BuyMax)
      {
         rejectReason = "RSI out of range (" + DoubleToString(rs, 1) + " not in " + DoubleToString(InpRSI_BuyMin, 1) + "-" + DoubleToString(InpRSI_BuyMax, 1) + ")";
         if(InpLogSignalAnalysis) DebugLog("BUY REJECT: " + rejectReason);
         return false;
      }
   }

   // Price action confirmation
   if(!CheckCandlePattern(true)) return false;

   // EMA crossover or strong alignment
   bool crossUp = (fast[2] <= slow[2]) && (fast[1] > slow[1]);
   bool strongTrend = (fast[1] > slow[1]) && (fast[1] > fast[2]) && (slow[1] > slow[2]);
   
   if(!crossUp && !strongTrend)
   {
      rejectReason = "No entry pattern (no cross, no strong trend)";
      if(InpLogSignalAnalysis) DebugLog("BUY REJECT: " + rejectReason);
      return false;
   }

   if(InpLogSignalAnalysis)
   {
      string pattern = crossUp ? "EMA_CROSS" : "STRONG_TREND";
      DebugLog("BUY CONFIRMED: " + pattern + " | Fast=" + DoubleToString(fast[1], 2) + 
         " Slow=" + DoubleToString(slow[1], 2) + " RSI=" + DoubleToString(rs, 1) + 
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

   string rejectReason = "";

   double atrPts = at / _Point;
   if(InpAvoidHighVolatility && atrPts > InpMaxATRPoints)
   {
      rejectReason = "High volatility";
      if(InpLogSignalAnalysis) DebugLog("SELL REJECT: " + rejectReason);
      return false;
   }
   if(InpAvoidLowVolatility && atrPts < InpMinATRPoints)
   {
      rejectReason = "Low volatility";
      if(InpLogSignalAnalysis) DebugLog("SELL REJECT: " + rejectReason);
      return false;
   }

   if(InpAvoidChoppyMarket && adx < InpMinADX)
   {
      rejectReason = "Choppy market";
      if(InpLogSignalAnalysis) DebugLog("SELL REJECT: " + rejectReason);
      return false;
   }

   if(InpRequireTrendAlignment && fast[1] >= slow[1])
   {
      rejectReason = "No trend alignment";
      if(InpLogSignalAnalysis) DebugLog("SELL REJECT: " + rejectReason);
      return false;
   }

   if(InpRequireStrongMomentum && mom > -InpMinMomentumThreshold)
   {
      rejectReason = "Weak momentum";
      if(InpLogSignalAnalysis) DebugLog("SELL REJECT: " + rejectReason);
      return false;
   }

   if(InpRequireRSIConfirmation)
   {
      if(rs < InpRSI_SellMin || rs > InpRSI_SellMax)
      {
         rejectReason = "RSI out of range";
         if(InpLogSignalAnalysis) DebugLog("SELL REJECT: " + rejectReason);
         return false;
      }
   }

   if(!CheckCandlePattern(false)) return false;

   bool crossDown = (fast[2] >= slow[2]) && (fast[1] < slow[1]);
   bool strongTrend = (fast[1] < slow[1]) && (fast[1] < fast[2]) && (slow[1] < slow[2]);
   
   if(!crossDown && !strongTrend)
   {
      rejectReason = "No entry pattern";
      if(InpLogSignalAnalysis) DebugLog("SELL REJECT: " + rejectReason);
      return false;
   }

   if(InpLogSignalAnalysis)
   {
      string pattern = crossDown ? "EMA_CROSS" : "STRONG_TREND";
      DebugLog("SELL CONFIRMED: " + pattern + " | Fast=" + DoubleToString(fast[1], 2) + 
         " Slow=" + DoubleToString(slow[1], 2) + " RSI=" + DoubleToString(rs, 1) + 
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
   
   DebugLog("OPENING " + side + " | Lot=" + DoubleToString(lots, 2) + 
      " Entry=" + DoubleToString(entry, _Digits) + " SL=" + IntegerToString(slPts) + "pts" + 
      " TP=" + IntegerToString(tpPts) + "pts Spread=" + IntegerToString(spread));

   bool ok = false;
   if(isBuy) ok = trade.Buy(lots, _Symbol, entry, sl, tp, "LowBudget BUY");
   else      ok = trade.Sell(lots, _Symbol, entry, sl, tp, "LowBudget SELL");

   if(ok)
   {
      g_lastTradeTime = TimeCurrent();
      ResetDailyCountersIfNeeded();
      g_tradesToday++;
      DebugLog("✓ OPENED " + side + " #" + IntegerToString(trade.ResultOrder()) + 
         " | Today: " + IntegerToString(g_tradesToday) + " trades, " + 
         IntegerToString(g_winsToday) + "W/" + IntegerToString(g_lossesToday) + "L");
   }
   else
   {
      DebugLog("✗ FAILED " + side + " retcode=" + IntegerToString(trade.ResultRetcode()) + 
         " " + trade.ResultRetcodeDescription());
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
         if(StringFind(comment, "PARTIAL_CLOSED") < 0)
         {
            double closeVol = NormalizeVolume(lots * InpPartialClosePercent / 100.0);
            if(closeVol >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            {
               trade.SetExpertMagicNumber(InpMagic);
               if(trade.PositionClosePartial(ticket, closeVol))
               {
                  DebugLog("✓ PARTIAL CLOSE " + DoubleToString(closeVol, 2) + " lots at +" + 
                     DoubleToString(profitPts, 0) + " pts");
                  
                  // Modify comment to mark partial close
                  trade.PositionModify(ticket, sl, tp);
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

      if(newSL != sl && MathAbs(newSL - sl) > _Point * 5)
      {
         trade.SetExpertMagicNumber(InpMagic);
         if(trade.PositionModify(ticket, newSL, tp))
         {
            DebugLog("✓ SL MOVED to " + DoubleToString(newSL, _Digits) + 
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
   g_todayDoy = CurrentDoy();
   g_tradesToday = 0;
   g_winsToday = 0;
   g_lossesToday = 0;

   Print("╔════════════════════════════════════════════════╗");
   Print("║   LOW-BUDGET SCALPER v2.10 INITIALIZED         ║");
   Print("╚════════════════════════════════════════════════╝");
   Print("Strategy: High Win-Rate Scalping");
   Print("Target: Small consistent profits");
   Print("SL: ", InpScalpSL_Points, " pts | TP: ", InpScalpTP_Points, " pts");
   Print("Max Spread: ", InpMaxSpreadPoints, " pts");
   Print("Session: ", InpUseSessionFilter ? (IntegerToString(InpTradeStartHour) + "-" + IntegerToString(InpTradeEndHour)) : "24/7");
   Print("Max Daily Losses: ", InpMaxDailyLoss);
   Print("Daily Profit Target: ", InpMaxDailyProfit, " wins");
   Print("═══════════════════════════════════════════════");

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

   Print("Low-Budget Scalper deinitialized");
}

void OnTick()
{
   if(!IsXAUUSD(_Symbol)) return;

   ManagePosition();

   if(!IsNewBar()) return;

   int spreadPts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
   if(!SpreadOK())
   {
      DebugLog("SKIP: Spread too high (" + IntegerToString(spreadPts) + " > " + IntegerToString(InpMaxSpreadPoints) + ")");
      return;
   }

   if(!TradingHoursOK())
   {
      if(InpLogSessionStatus)
         DebugLog("SKIP: Outside trading hours");
      return;
   }

   if(!CooldownOK())
   {
      int remaining = InpCooldownSeconds - (int)(TimeCurrent() - g_lastTradeTime);
      DebugLog("SKIP: Cooldown (" + IntegerToString(remaining) + "s remaining)");
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
      DebugLog("SKIP: Conflicting signals");
      return;
   }

   if(buySignal) OpenTrade(true);
   if(sellSignal) OpenTrade(false);
}
//+------------------------------------------------------------------+
