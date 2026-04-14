//USTEC-M15
//ORB Trading system based on Paper -> https://papers.ssrn.com/sol3/papers.cfm?abstract_id=4631351
#include <Trade/Trade.mqh>
CTrade trade;

// --- Entry time ---
input int startHour        = 16;
input int startMinute      = 35;

// --- Closing window ---
input int closeStartHour   = 21;
input int closeStartMinute = 50;
input int closeEndHour     = 22;
input int closeEndMinute   = 55;

// --- RSI close filter (independent timeframe) ---
input ENUM_TIMEFRAMES rsiTimeframe = PERIOD_M15;
input int             rsiPeriod    = 14;
input double          rsiBuyClose  = 90.0;
input double          rsiSellClose = 10.0;

// --- Profit target ---
input double profitTargetPct = 1.0;

// --- Breakeven ---
input bool   useBreakeven        = true;
input double breakevenMultiplier = 1.0;

// --- Day filter ---
input bool allowMonday    = true;
input bool allowTuesday   = true;
input bool allowWednesday = true;
input bool allowThursday  = true;
input bool allowFriday    = true;

// --- Strategy ---
input double risk      = 2.0;
input double slp       = 0.004;
input int    MaPeriods = 250;
input int    Magic     = 998877;

int    barsTotal = 0;
int    handleMa;
int    handleRsi;
double lastClose = 0;
double lot       = 0.1;

//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(Magic);
    handleMa  = iMA (_Symbol, PERIOD_CURRENT, MaPeriods, 0, MODE_SMA, PRICE_CLOSE);
    handleRsi = iRSI(_Symbol, rsiTimeframe, rsiPeriod, PRICE_CLOSE);
    if(handleMa == INVALID_HANDLE || handleRsi == INVALID_HANDLE)
    {
        Print("Failed to create indicator handles.");
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(handleMa);
    IndicatorRelease(handleRsi);
}

//+------------------------------------------------------------------+
void OnTick()
{
    // --- Every tick ---
    if(useBreakeven)      CheckBreakeven();
    if(InClosingWindow()) CheckRsiClose();
    CheckProfitTarget();

    // --- New bar only ---
    int bars = iBars(_Symbol, PERIOD_CURRENT);
    if(barsTotal != bars)
    {
        barsTotal = bars;

        bool   NotInPosition = true;
        double ma[];
        CopyBuffer(handleMa, 0, 1, 1, ma);

        if(MarketOpened() && !InClosingWindow())
        {
            lastClose = iClose(_Symbol, PERIOD_CURRENT, 1);
            int    startIndex = getSessionStartIndex();
            double vwap       = getVWAP(startIndex);

            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
                ulong  pos = PositionGetTicket(i);
                string sym = PositionGetSymbol(i);
                if(PositionGetInteger(POSITION_MAGIC) == Magic && sym == _Symbol)
                {
                    if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY  && lastClose < vwap) ||
                       (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && lastClose > vwap))
                        trade.PositionClose(pos);
                    else
                        NotInPosition = false;
                }
            }

            if(IsDayAllowed())
            {
                if(lastClose < vwap && NotInPosition && lastClose < ma[0]) executeSell();
                if(lastClose > vwap && NotInPosition && lastClose > ma[0]) executeBuy();
            }
        }
    }
}

//+------------------------------------------------------------------+
void CheckRsiClose()
{
    double rsi[];
    CopyBuffer(handleRsi, 0, 0, 1, rsi);  // index 0 = live bar on rsiTimeframe
    double rsiVal      = rsi[0];
    bool   isWindowEnd = IsClosingWindowEnd();

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong  pos = PositionGetTicket(i);
        string sym = PositionGetSymbol(i);
        if(PositionGetInteger(POSITION_MAGIC) != Magic || sym != _Symbol) continue;

        long pType     = PositionGetInteger(POSITION_TYPE);
        bool closeBuy  = (pType == POSITION_TYPE_BUY  && rsiVal >= rsiBuyClose);
        bool closeSell = (pType == POSITION_TYPE_SELL && rsiVal <= rsiSellClose);

        if(closeBuy || closeSell || isWindowEnd)
            trade.PositionClose(pos);
    }
}

//+------------------------------------------------------------------+
void CheckProfitTarget()
{
    double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
    double targetAmount = balance * profitTargetPct / 100.0;
    double totalProfit  = 0.0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong  pos = PositionGetTicket(i);
        string sym = PositionGetSymbol(i);
        if(PositionGetInteger(POSITION_MAGIC) == Magic && sym == _Symbol)
            totalProfit += PositionGetDouble(POSITION_PROFIT);
    }

    if(totalProfit >= targetAmount)
    {
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong  pos = PositionGetTicket(i);
            string sym = PositionGetSymbol(i);
            if(PositionGetInteger(POSITION_MAGIC) == Magic && sym == _Symbol)
                trade.PositionClose(pos);
        }
    }
}

//+------------------------------------------------------------------+
void CheckBreakeven()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong  pos   = PositionGetTicket(i);
        string sym   = PositionGetSymbol(i);
        if(PositionGetInteger(POSITION_MAGIC) != Magic || sym != _Symbol) continue;

        double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl    = PositionGetDouble(POSITION_SL);
        long   pType = PositionGetInteger(POSITION_TYPE);

        if(pType == POSITION_TYPE_BUY)
        {
            double slDistance = entry - sl;
            double target     = entry + slDistance * breakevenMultiplier;
            double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            if(currentBid >= target && sl < entry)
                trade.PositionModify(pos, NormalizeDouble(entry, _Digits), 0);
        }
        else if(pType == POSITION_TYPE_SELL)
        {
            double slDistance = sl - entry;
            double target     = entry - slDistance * breakevenMultiplier;
            double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            if(currentAsk <= target && sl > entry)
                trade.PositionModify(pos, NormalizeDouble(entry, _Digits), 0);
        }
    }
}

//+------------------------------------------------------------------+
bool MarketOpened()
{
    MqlDateTime t;
    TimeToStruct(TimeTradeServer(), t);
    return (t.hour >= startHour && t.min >= startMinute);
}

//+------------------------------------------------------------------+
bool InClosingWindow()
{
    MqlDateTime t;
    TimeToStruct(TimeTradeServer(), t);
    int now   = t.hour * 60 + t.min;
    int start = closeStartHour * 60 + closeStartMinute;
    int end   = closeEndHour   * 60 + closeEndMinute;
    return (now >= start && now <= end);
}

//+------------------------------------------------------------------+
bool IsClosingWindowEnd()
{
    MqlDateTime t;
    TimeToStruct(TimeTradeServer(), t);
    return (t.hour == closeEndHour && t.min == closeEndMinute);
}

//+------------------------------------------------------------------+
bool IsDayAllowed()
{
    MqlDateTime t;
    TimeToStruct(TimeTradeServer(), t);
    switch(t.day_of_week)
    {
        case 1: return allowMonday;
        case 2: return allowTuesday;
        case 3: return allowWednesday;
        case 4: return allowThursday;
        case 5: return allowFriday;
        default: return false;
    }
}

//+------------------------------------------------------------------+
void executeSell()
{
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    bid = NormalizeDouble(bid, _Digits);
    double sl = bid * (1 + slp);
    sl = NormalizeDouble(sl, _Digits);
    lot = calclots(bid * slp);
    trade.Sell(lot, _Symbol, bid, sl);
}

//+------------------------------------------------------------------+
void executeBuy()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    ask = NormalizeDouble(ask, _Digits);
    double sl = ask * (1 - slp);
    sl = NormalizeDouble(sl, _Digits);
    lot = calclots(ask * slp);
    trade.Buy(lot, _Symbol, ask, sl);
}

//+------------------------------------------------------------------+
double getVWAP(int startCandle)
{
    double sumPV = 0.0;
    long   sumV  = 0;

    for(int i = startCandle; i >= 1; i--)
    {
        double high  = iHigh (_Symbol, PERIOD_CURRENT, i);
        double low   = iLow  (_Symbol, PERIOD_CURRENT, i);
        double close = iClose(_Symbol, PERIOD_CURRENT, i);
        double typicalPrice = (high + low + close) / 3.0;
        long   volume = iVolume(_Symbol, PERIOD_CURRENT, i);
        sumPV += typicalPrice * volume;
        sumV  += volume;
    }

    if(sumV == 0) return 0.0;

    double   vwap           = sumPV / sumV;
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    string   objName        = "VWAP" + TimeToString(currentBarTime, TIME_MINUTES);
    ObjectCreate(0, objName, OBJ_ARROW, 0, currentBarTime, vwap);
    ObjectSetInteger(0, objName, OBJPROP_COLOR, clrGreen);
    ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, 1);

    return vwap;
}

//+------------------------------------------------------------------+
int getSessionStartIndex()
{
    int sessionIndex = 1;
    for(int i = 1; i <= 1000; i++)
    {
        datetime    barTime = iTime(_Symbol, PERIOD_CURRENT, i);
        MqlDateTime dt;
        TimeToStruct(barTime, dt);
        if(dt.hour == startHour && dt.min == startMinute - 5)
        {
            sessionIndex = i;
            break;
        }
    }
    return sessionIndex;
}

//+------------------------------------------------------------------+
double calclots(double slpoints)
{
    double riskAmount      = AccountInfoDouble(ACCOUNT_BALANCE) * risk / 100;
    double ticksize        = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickvalue       = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotstep         = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double moneyperlotstep = slpoints / ticksize * tickvalue * lotstep;
    double lots            = MathFloor(riskAmount / moneyperlotstep) * lotstep;
    lots = MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
    lots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
    return lots;
}
