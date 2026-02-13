//+------------------------------------------------------------------+
//|                                      RSI_Stoch_Pro_Scalper.mq5    |
//|  Reversal scalper with bar-close confirmation, sessions,          |
//|  cooldowns, daily limits, and modern solid dashboard.            |
//|                                                                  |
//|  Dashboard v2.01 - Status Alignment Fix:                         |
//|  - Fixed status pill vertical centering                          |
//|  - Improved header layout spacing                                |
//|  - Better text anchor positioning for status badge               |
//|                                                                  |
//|  Notes: "Chance" is an informative meter only, not probability.  |
//+------------------------------------------------------------------+
#property strict
#property version   "2.01"
#property description "RSI+Stoch reversal scalper with modern aligned dashboard."

#include <Trade\Trade.mqh>

//-----------------------------
// Input Groups
//-----------------------------
input group "=== General ==="
input ulong  MagicNumber               = 2026021301;
input string TradeComment              = "RSI_Stoch_Pro_Scalper";
input bool   OnePositionPerSymbol      = true;

input group "=== Timeframe ==="
input ENUM_TIMEFRAMES SignalTimeframe  = PERIOD_M5;

input group "=== Indicators ==="
input int    RsiPeriod                 = 14;
input int    StochKPeriod              = 5;
input int    StochDPeriod              = 3;
input int    StochSlowing              = 3;

input group "=== Zones ==="
input double RsiBuyMax                 = 30.0;
input double RsiSellMin                = 70.0;
input double StochOversold             = 20.0;
input double StochOverbought           = 80.0;

input group "=== Session Filter ==="
input bool   UseAsiaSession            = false;
input bool   UseLondonSession          = true;
input bool   UseNYSession              = true;
input int    AsiaStartHour             = 0;
input int    AsiaEndHour               = 8;
input int    LondonStartHour           = 8;
input int    LondonEndHour             = 16;
input int    NYStartHour               = 13;
input int    NYEndHour                 = 22;

input group "=== Cooldowns ==="
input int    StartupCooldownSeconds    = 60;
input int    PostTradeCooldownSeconds  = 350;

input group "=== Risk Management ==="
input double Lots                      = 0.01;
input int    StopLossPoints            = 100;
input double RiskRewardRatio           = 2.0;

input group "=== Daily Limits ==="
input double DailyProfitTarget_USD     = 50.0;
input double DailyLossLimit_USD        = 30.0;
input int    MaxDailyTrades            = 10;

input group "=== Dashboard Settings ==="
input bool   DashboardEnabled          = true;
input int    Dashboard_X               = 20;
input int    Dashboard_Y               = 20;
input int    Dashboard_Width           = 400;
input bool   DashboardTopLeft          = true;

//-----------------------------
// Dashboard Object Names
//-----------------------------
#define DBG_SHADOW    "RSP_DBG_SHADOW"
#define DBG_BG        "RSP_DBG_BG"
#define DBG_HEADER    "RSP_DBG_HEADER"
#define DBG_ACCENT    "RSP_DBG_ACCENT"
#define DBG_TITLE     "RSP_DBG_TITLE"
#define DBG_STATUS    "RSP_DBG_STATUS"
#define DBG_STATUS_TX "RSP_DBG_STATUS_TX"

// Grid Layout Objects
#define DBG_R1_LABEL  "RSP_DBG_R1_L"
#define DBG_R1_VALUE  "RSP_DBG_R1_V"
#define DBG_R1_LABEL2 "RSP_DBG_R1_L2"
#define DBG_R1_VALUE2 "RSP_DBG_R1_V2"

#define DBG_R2_LABEL  "RSP_DBG_R2_L"
#define DBG_R2_VALUE  "RSP_DBG_R2_V"
#define DBG_R2_LABEL2 "RSP_DBG_R2_L2"
#define DBG_R2_VALUE2 "RSP_DBG_R2_V2"

#define DBG_R3_LABEL  "RSP_DBG_R3_L"
#define DBG_R3_VALUE  "RSP_DBG_R3_V"

#define DBG_R4_LABEL  "RSP_DBG_R4_L"
#define DBG_R4_VALUE  "RSP_DBG_R4_V"

#define DBG_DIVIDER   "RSP_DBG_DIV"
#define DBG_METER_LBL "RSP_DBG_MLBL"
#define DBG_METER_BG  "RSP_DBG_MBG"
#define DBG_METER_FG  "RSP_DBG_MFG"
#define DBG_FOOTER    "RSP_DBG_FOOT"

//-----------------------------
// Globals
//-----------------------------
CTrade   Trade;

int      g_rsiHandle      = INVALID_HANDLE;
int      g_stochHandle    = INVALID_HANDLE;
datetime g_initTime       = 0;
datetime g_lastSignalBar  = 0;
datetime g_lastDayReset   = 0;
double   g_todayProfit    = 0;
int      g_todayTrades    = 0;
datetime g_lastCloseTime  = 0;

enum ENUM_EA_STATUS
{
   STATUS_SCANNING,
   STATUS_COOLDOWN,
   STATUS_SLEEPING,
   STATUS_LIMIT
};

//-----------------------------
// Utility Functions
//-----------------------------
datetime DayStart(datetime t)
{
   MqlDateTime dt; 
   TimeToStruct(t, dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   return StructToTime(dt);
}

bool IsWithinSession(datetime t)
{
   if(!UseAsiaSession && !UseLondonSession && !UseNYSession) return true;
   
   MqlDateTime dt; 
   TimeToStruct(t, dt);
   int h = dt.hour;
   
   if(UseAsiaSession   && IsWithinHours(h, AsiaStartHour,   AsiaEndHour))   return true;
   if(UseLondonSession && IsWithinHours(h, LondonStartHour, LondonEndHour)) return true;
   if(UseNYSession     && IsWithinHours(h, NYStartHour,     NYEndHour))     return true;
   
   return false;
}

bool IsWithinHours(int h, int start, int end)
{
   start = (start % 24 + 24) % 24;
   end   = (end   % 24 + 24) % 24;
   if(start == end) return true;
   if(start < end)  return (h >= start && h < end);
   return (h >= start || h < end);
}

bool HasOpenPosition()
{
   if(!OnePositionPerSymbol) return false;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      return true;
   }
   return false;
}

double NormalizePrice(double p)
{
   return NormalizeDouble(p, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

bool CheckStops(bool isBuy, double entry, double sl, double tp)
{
   int level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(level <= 0) return true;
   
   double min = level * _Point;
   if(isBuy)
      return (entry - sl >= min) && (tp - entry >= min);
   else
      return (sl - entry >= min) && (entry - tp >= min);
}

string SessionName()
{
   MqlDateTime dt; 
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   
   string s = "";
   if(UseAsiaSession   && IsWithinHours(h, AsiaStartHour,   AsiaEndHour))   s += "Asia ";
   if(UseLondonSession && IsWithinHours(h, LondonStartHour, LondonEndHour)) s += "London ";
   if(UseNYSession     && IsWithinHours(h, NYStartHour,     NYEndHour))     s += "NY ";
   
   return (s == "") ? "Closed" : s;
}

int CooldownRemaining(ENUM_EA_STATUS st)
{
   if(st != STATUS_COOLDOWN) return 0;
   datetime now = TimeCurrent();
   int rem1 = (int)MathMax(0, StartupCooldownSeconds - (int)(now - g_initTime));
   int rem2 = (g_lastCloseTime > 0) ? (int)MathMax(0, PostTradeCooldownSeconds - (int)(now - g_lastCloseTime)) : 0;
   return MathMax(rem1, rem2);
}

void ComputeStats()
{
   datetime start = DayStart(TimeCurrent());
   if(!HistorySelect(start, TimeCurrent())) return;
   
   g_todayProfit = 0;
   g_todayTrades = 0;
   g_lastCloseTime = 0;
   
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; ++i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      
      long type = HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
      
      g_todayProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT) 
                     + HistoryDealGetDouble(ticket, DEAL_SWAP) 
                     + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      g_todayTrades++;
      
      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(t > g_lastCloseTime) g_lastCloseTime = t;
   }
}

ENUM_EA_STATUS GetStatus()
{
   datetime now = TimeCurrent();
   
   // Day reset
   datetime day0 = DayStart(now);
   if(day0 != g_lastDayReset)
   {
      g_lastDayReset = day0;
      ComputeStats();
   }
   
   // Check limits
   if(DailyProfitTarget_USD > 0 && g_todayProfit >= DailyProfitTarget_USD) return STATUS_LIMIT;
   if(DailyLossLimit_USD > 0 && g_todayProfit <= -DailyLossLimit_USD) return STATUS_LIMIT;
   if(MaxDailyTrades > 0 && g_todayTrades >= MaxDailyTrades) return STATUS_LIMIT;
   
   // Session
   if(!IsWithinSession(now)) return STATUS_SLEEPING;
   
   // Cooldowns
   if((now - g_initTime) < StartupCooldownSeconds) return STATUS_COOLDOWN;
   if(g_lastCloseTime > 0 && (now - g_lastCloseTime) < PostTradeCooldownSeconds) return STATUS_COOLDOWN;
   
   return STATUS_SCANNING;
}

color GetStatusColor(ENUM_EA_STATUS s)
{
   switch(s)
   {
      case STATUS_SCANNING: return C'76,175,80';   // Green
      case STATUS_COOLDOWN: return C'255,160,0';   // Orange
      case STATUS_SLEEPING: return C'120,120,130'; // Gray
      case STATUS_LIMIT:    return C'244,67,54';   // Red
   }
   return clrGray;
}

string GetStatusText(ENUM_EA_STATUS s)
{
   switch(s)
   {
      case STATUS_SCANNING: return "SCANNING";
      case STATUS_COOLDOWN: return "COOLDOWN";
      case STATUS_SLEEPING: return "SLEEPING";
      case STATUS_LIMIT:    return "LIMIT HIT";
   }
   return "UNKNOWN";
}

//-----------------------------
// Indicator Functions
//-----------------------------
bool GetIndiValues(double &rsi1, double &k1, double &d1, double &k2, double &d2)
{
   if(g_rsiHandle == INVALID_HANDLE || g_stochHandle == INVALID_HANDLE) return false;
   
   double rsiBuf[2];
   if(CopyBuffer(g_rsiHandle, 0, 0, 2, rsiBuf) != 2) return false;
   rsi1 = rsiBuf[1];
   
   double kBuf[3], dBuf[3];
   if(CopyBuffer(g_stochHandle, 0, 0, 3, kBuf) != 3) return false;
   if(CopyBuffer(g_stochHandle, 1, 0, 3, dBuf) != 3) return false;
   
   k1 = kBuf[1]; d1 = dBuf[1];
   k2 = kBuf[2]; d2 = dBuf[2];
   
   return true;
}

bool IsNewBar()
{
   datetime t1 = iTime(_Symbol, SignalTimeframe, 1);
   if(t1 != g_lastSignalBar)
   {
      g_lastSignalBar = t1;
      return true;
   }
   return false;
}

bool CrossUp(double k0, double d0, double k1, double d1)
{
   return (k0 <= d0 && k1 > d1);
}

bool CrossDown(double k0, double d0, double k1, double d1)
{
   return (k0 >= d0 && k1 < d1);
}

int CalcSignalChance(bool ok, double rsi, double k, double d, double kPrev, double dPrev)
{
   if(!ok) return 0;
   
   // Buy score
   double rsiScore = (rsi <= RsiBuyMax) ? 1.0 : MathMax(0, 1.0 - (rsi - RsiBuyMax)/20.0);
   double stScore  = (k <= StochOversold) ? 1.0 : MathMax(0, 1.0 - (k - StochOversold)/30.0);
   double buyChance = 0.55*rsiScore + 0.45*stScore;
   if(CrossUp(kPrev, dPrev, k, d)) buyChance += 0.2;
   buyChance = MathMin(1.0, buyChance);
   
   // Sell score
   rsiScore = (rsi >= RsiSellMin) ? 1.0 : MathMax(0, 1.0 - (RsiSellMin - rsi)/20.0);
   stScore  = (k >= StochOverbought) ? 1.0 : MathMax(0, 1.0 - (StochOverbought - k)/30.0);
   double sellChance = 0.55*rsiScore + 0.45*stScore;
   if(CrossDown(kPrev, dPrev, k, d)) sellChance += 0.2;
   sellChance = MathMin(1.0, sellChance);
   
   return (int)MathRound(MathMax(buyChance, sellChance) * 100.0);
}

//-----------------------------
// Dashboard Functions
//-----------------------------
int Corner() { return DashboardTopLeft ? CORNER_LEFT_UPPER : CORNER_RIGHT_UPPER; }

void CreateRect(string name, int x, int y, int w, int h, color bg, color border, int z)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      
   ObjectSetInteger(0, name, OBJPROP_CORNER, Corner());
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BACK, false); // Solid!
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, z);
}

void CreateLabel(string name, int x, int y, string text, int size, color clr, int z, bool bold=false)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      
   ObjectSetInteger(0, name, OBJPROP_CORNER, Corner());
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, z);
}

void SetTxt(string name, string text)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void DashboardCreate()
{
   if(!DashboardEnabled) return;
   
   // Palette
   color cBg        = C'30,30,34';
   color cShadow    = C'18,18,22';
   color cHeader    = C'40,40,44';
   color cBorder    = C'55,55,60';
   color cLabel     = C'150,150,160';
   color cValue     = C'245,245,250';
   color cAccent    = C'76,175,80';
   
   int x = Dashboard_X;
   int y = Dashboard_Y;
   int w = Dashboard_Width;
   int h = 240;
   
   // Layout constants
   int pad = 15;
   int rowH = 24;
   int headerH = 40;
   int col1X = x + pad;
   int col1ValX = x + 85;
   int col2X = x + 220;
   int col2ValX = x + 280;
   int contentY = y + headerH + 18;
   
   // 1. Shadow
   CreateRect(DBG_SHADOW, x+3, y+3, w, h, cShadow, cShadow, 0);
   
   // 2. Main Background
   CreateRect(DBG_BG, x, y, w, h, cBg, cBorder, 1);
   
   // 3. Header
   CreateRect(DBG_HEADER, x, y, w, headerH, cHeader, cBorder, 2);
   
   // 4. Accent line
   CreateRect(DBG_ACCENT, x, y+headerH-2, w, 2, cAccent, cAccent, 3);
   
   // 5. Title
   CreateLabel(DBG_TITLE, x+pad, y+12, "RSI Stoch Pro Scalper", 11, cValue, 4, true);
   
   // 6. Status Pill - Fixed positioning for better alignment
   int pillW = 100;
   int pillH = 24;
   int pillX = x + w - pillW - pad;
   int pillY = y + (headerH - pillH) / 2; // Vertically centered in header
   
   CreateRect(DBG_STATUS, pillX, pillY, pillW, pillH, cAccent, C'0,0,0', 4);
   
   // Text centered in pill using anchor
   CreateLabel(DBG_STATUS_TX, pillX + pillW/2, pillY + pillH/2 + 1, "SCANNING", 9, C'0,0,0', 5, true);
   ObjectSetInteger(0, DBG_STATUS_TX, OBJPROP_ANCHOR, ANCHOR_CENTER);
   
   // 7. Grid Content - Row 1: Time | Session
   CreateLabel(DBG_R1_LABEL, col1X, contentY, "Time", 9, cLabel, 3);
   CreateLabel(DBG_R1_VALUE, col1ValX, contentY, "--:--:--", 9, cValue, 3);
   CreateLabel(DBG_R1_LABEL2, col2X, contentY, "Session", 9, cLabel, 3);
   CreateLabel(DBG_R1_VALUE2, col2ValX, contentY, "-", 9, cValue, 3);
   
   // Row 2: Symbol | Spread
   CreateLabel(DBG_R2_LABEL, col1X, contentY+rowH, "Symbol", 9, cLabel, 3);
   CreateLabel(DBG_R2_VALUE, col1ValX, contentY+rowH, "-", 9, cValue, 3);
   CreateLabel(DBG_R2_LABEL2, col2X, contentY+rowH, "Spread", 9, cLabel, 3);
   CreateLabel(DBG_R2_VALUE2, col2ValX, contentY+rowH, "-", 9, cValue, 3);
   
   // Row 3: RSI
   CreateLabel(DBG_R3_LABEL, col1X, contentY+rowH*2, "RSI (14)", 9, cLabel, 3);
   CreateLabel(DBG_R3_VALUE, col1ValX, contentY+rowH*2, "-", 9, cValue, 3);
   
   // Row 4: Stoch
   CreateLabel(DBG_R4_LABEL, col1X, contentY+rowH*3, "Stoch K/D", 9, cLabel, 3);
   CreateLabel(DBG_R4_VALUE, col1ValX, contentY+rowH*3, "-", 9, cValue, 3);
   
   // 8. Divider
   int divY = y + h - 70;
   CreateRect(DBG_DIVIDER, x+pad, divY, w-pad*2, 1, C'55,55,60', C'55,55,60', 2);
   
   // 9. Signal Meter
   int meterY = divY + 12;
   int meterW = w - pad*2;
   int meterH = 8;
   CreateLabel(DBG_METER_LBL, x+pad, meterY-2, "Signal Strength: 0%", 9, cLabel, 4);
   CreateRect(DBG_METER_BG, x+pad, meterY+14, meterW, meterH, C'50,50,55', C'50,50,55', 2);
   CreateRect(DBG_METER_FG, x+pad, meterY+14, 0, meterH, C'76,175,80', C'76,175,80', 3);
   
   // 10. Footer
   CreateLabel(DBG_FOOTER, x+pad, y+h-22, "Today P/L: $0.00 | Trades: 0/"+IntegerToString(MaxDailyTrades), 9, cValue, 4);
   
   Comment("");
}

void DashboardUpdate()
{
   if(!DashboardEnabled) { Comment(""); return; }
   
   // Get data
   ENUM_EA_STATUS status = GetStatus();
   double rsi=0, k=0, d=0, kPrev=0, dPrev=0;
   bool indOk = GetIndiValues(rsi, k, d, kPrev, dPrev);
   int chance = CalcSignalChance(indOk, rsi, k, d, kPrev, dPrev);
   color accent = GetStatusColor(status);
   
   // Update accent line
   ObjectSetInteger(0, DBG_ACCENT, OBJPROP_BGCOLOR, accent);
   ObjectSetInteger(0, DBG_ACCENT, OBJPROP_COLOR, accent);
   
   // Update status pill color
   ObjectSetInteger(0, DBG_STATUS, OBJPROP_BGCOLOR, accent);
   SetTxt(DBG_STATUS_TX, GetStatusText(status));
   
   // Update status text color based on background brightness
   color txtColor = (status == STATUS_SCANNING || status == STATUS_COOLDOWN) ? C'0,0,0' : C'255,255,255';
   ObjectSetInteger(0, DBG_STATUS_TX, OBJPROP_COLOR, txtColor);
   
   // Update Time
   string tstr = TimeToString(TimeCurrent(), TIME_SECONDS);
   int cd = CooldownRemaining(status);
   if(cd > 0) tstr += " [CD: " + IntegerToString(cd) + "s]";
   SetTxt(DBG_R1_VALUE, tstr);
   
   // Update Session
   SetTxt(DBG_R1_VALUE2, SessionName());
   
   // Update Symbol/TF
   string tf = StringSubstr(EnumToString(SignalTimeframe), 7);
   SetTxt(DBG_R2_VALUE, _Symbol + " / " + tf);
   
   // Update Spread
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
   SetTxt(DBG_R2_VALUE2, DoubleToString(spread, 1) + " pts");
   
   // Update RSI
   if(indOk)
      SetTxt(DBG_R3_VALUE, DoubleToString(rsi,2) + "  [Buy<" + DoubleToString(RsiBuyMax,0) + " | Sell>" + DoubleToString(RsiSellMin,0) + "]");
   else
      SetTxt(DBG_R3_VALUE, "Loading...");
   
   // Update Stoch
   if(indOk)
      SetTxt(DBG_R4_VALUE, DoubleToString(k,2) + " / " + DoubleToString(d,2) + "  [OS<" + DoubleToString(StochOversold,0) + " | OB>" + DoubleToString(StochOverbought,0) + "]");
   else
      SetTxt(DBG_R4_VALUE, "Loading...");
   
   // Update Meter
   SetTxt(DBG_METER_LBL, "Signal Strength: " + IntegerToString(chance) + "%");
   int mw = Dashboard_Width - 30;
   int fillW = (int)((chance / 100.0) * mw);
   fillW = MathMax(fillW, 1);
   
   color mc;
   if(chance < 30) mc = C'244,67,54';
   else if(chance < 60) mc = C'255,160,0';
   else mc = C'76,175,80';
   
   ObjectSetInteger(0, DBG_METER_FG, OBJPROP_BGCOLOR, mc);
   ObjectSetInteger(0, DBG_METER_FG, OBJPROP_COLOR, mc);
   ObjectSetInteger(0, DBG_METER_FG, OBJPROP_XSIZE, fillW);
   
   // Update Footer
   string pl = (g_todayProfit >= 0 ? "+" : "") + DoubleToString(g_todayProfit,2);
   SetTxt(DBG_FOOTER, "Today P/L: $" + pl + " | Trades: " + IntegerToString(g_todayTrades) + "/" + IntegerToString(MaxDailyTrades));
   
   Comment("");
}

void DashboardDelete()
{
   string objs[] = {
      DBG_FOOTER, DBG_METER_FG, DBG_METER_BG, DBG_METER_LBL, DBG_DIVIDER,
      DBG_R4_VALUE, DBG_R4_LABEL, DBG_R3_VALUE, DBG_R3_LABEL,
      DBG_R2_VALUE2, DBG_R2_LABEL2, DBG_R2_VALUE, DBG_R2_LABEL,
      DBG_R1_VALUE2, DBG_R1_LABEL2, DBG_R1_VALUE, DBG_R1_LABEL,
      DBG_STATUS_TX, DBG_STATUS, DBG_TITLE, DBG_ACCENT, DBG_HEADER, DBG_BG, DBG_SHADOW
   };
   for(int i=0; i<ArraySize(objs); i++)
      ObjectDelete(0, objs[i]);
   Comment("");
}

//-----------------------------
// Trade Functions
//-----------------------------
bool OpenBuy()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = entry - StopLossPoints * _Point;
   double tp = entry + StopLossPoints * RiskRewardRatio * _Point;
   entry = NormalizePrice(entry);
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   
   if(!CheckStops(true, entry, sl, tp))
   {
      Print("BUY rejected: stops too close");
      return false;
   }
   
   Trade.SetExpertMagicNumber(MagicNumber);
   if(!Trade.Buy(Lots, _Symbol, entry, sl, tp, TradeComment))
   {
      Print("BUY failed: ", Trade.ResultRetcode());
      return false;
   }
   Print("BUY opened @", entry, " SL:", sl, " TP:", tp);
   return true;
}

bool OpenSell()
{
   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl = entry + StopLossPoints * _Point;
   double tp = entry - StopLossPoints * RiskRewardRatio * _Point;
   entry = NormalizePrice(entry);
   sl = NormalizePrice(sl);
   tp = NormalizePrice(tp);
   
   if(!CheckStops(false, entry, sl, tp))
   {
      Print("SELL rejected: stops too close");
      return false;
   }
   
   Trade.SetExpertMagicNumber(MagicNumber);
   if(!Trade.Sell(Lots, _Symbol, entry, sl, tp, TradeComment))
   {
      Print("SELL failed: ", Trade.ResultRetcode());
      return false;
   }
   Print("SELL opened @", entry, " SL:", sl, " TP:", tp);
   return true;
}

//-----------------------------
// Standard Handlers
//-----------------------------
int OnInit()
{
   g_initTime = TimeCurrent();
   g_lastDayReset = DayStart(g_initTime);
   
   g_rsiHandle = iRSI(_Symbol, SignalTimeframe, RsiPeriod, PRICE_CLOSE);
   g_stochHandle = iStochastic(_Symbol, SignalTimeframe, StochKPeriod, StochDPeriod, StochSlowing, MODE_SMA, STO_LOWHIGH);
   
   if(g_rsiHandle == INVALID_HANDLE || g_stochHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicator handles");
      return INIT_FAILED;
   }
   
   Trade.SetExpertMagicNumber(MagicNumber);
   ComputeStats();
   EventSetTimer(1);
   
   if(DashboardEnabled)
      DashboardCreate();
   
   Print("RSI_Stoch_Pro_Scalper v2.01 initialized");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(g_rsiHandle);
   IndicatorRelease(g_stochHandle);
   DashboardDelete();
   Print("Deinitialized. Reason:", reason);
}

void OnTimer()
{
   ComputeStats();
}

void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != MagicNumber) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   
   ComputeStats();
}

void OnTick()
{
   ComputeStats();
   DashboardUpdate();
   
   ENUM_EA_STATUS st = GetStatus();
   if(st != STATUS_SCANNING) return;
   if(!IsNewBar()) return;
   if(HasOpenPosition()) return;
   
   double rsi=0, k=0, d=0, kPrev=0, dPrev=0;
   if(!GetIndiValues(rsi, k, d, kPrev, dPrev)) return;
   
   bool up = CrossUp(kPrev, dPrev, k, d);
   bool down = CrossDown(kPrev, dPrev, k, d);
   
   if(rsi < RsiBuyMax && k < StochOversold && up)
   {
      Print("Signal: BUY | RSI:", rsi, " StochK:", k);
      OpenBuy();
   }
   else if(rsi > RsiSellMin && k > StochOverbought && down)
   {
      Print("Signal: SELL | RSI:", rsi, " StochK:", k);
      OpenSell();
   }
}
//+------------------------------------------------------------------+
