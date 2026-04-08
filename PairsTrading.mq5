//+------------------------------------------------------------------+
//+------------------------------------------------------------------+

#property version   "2.00"
#property strict

// Include necessary libraries
#include <Trade\Trade.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Math\Stat\Math.mqh>

// Input parameters for pair trading
input string Symbol1 = "EURUSD";     // The first symbol of the pair
input string Symbol2 = "GBPUSD";     // The second symbol of the pair
input double LotSize = 0.01;         // Lot Size (positioning)
input int ZScorePeriod = 100;        // Z-score calculation period
input double EntryThreshold = 2.0;   // Z-score entry threshold
input double ExitThreshold = 0.0;    // Z-score exit threshold
input int SpreadLimit = 10;          // Spread limit (in points)
input int CorrelationPeriod = 50;    // Period for tracking correlation
input double ProfitTarget = 1.0;     // Target profit in USD for closing the position
input bool EnableAveraging = true;   // Enable position averaging when correlation drops
input double CorrelationDropThreshold = 0.2; // Correlation drop threshold for averaging
input double AveragingLotMultiplier = 1.5;   // Lot multiplier for averaging
input bool EnableProtectiveStops = true;     // Enable protective stop orders
input int ProtectiveStopPips = 500;          // Protective stop size in pips
input bool EnableTakeProfit = true;          // Enable take profit
input int TakeProfitPips = 800;              // Take profit size in pips
input long MagicNumber = 123456;             // Magic number for positions

// Internal variables for optimization
int CurrentZScorePeriod;
double CurrentEntryThreshold;
double CurrentExitThreshold;

// Optimization
input bool AutoOptimize = true;      // Enable auto optimization
input int OptimizationPeriod = 5000; // Number of ticks between optimizations
input int MinDataPoints = 1000;      // Minimum number of points for optimization
input double RiskPercent = 1.0;      // Risk per trade (% of balance)
input int MaxConsecutiveLosses = 3;  // Max. trades execution if all lost

// Global variables
CTrade trade;
double prices1[], prices2[], ratio[], zscore[];
double correlationHistory[];
int tickCount = 0;
CArrayObj optimizationResults;
bool isPositionOpen = false;
int consecutiveLosses = 0;
double lastTradeProfit = 0;
ulong posTickets[];
int averagingCount = 0;
double initialCorrelation = 0.0;
double lastLotSize = 0.0;

// Class for storing optimization results
class OptimizationResult : public CObject
{
public:
    int zScorePeriod;
    double entryThreshold;
    double exitThreshold;
    double profit;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set a magic number for a trading object
    trade.SetExpertMagicNumber(MagicNumber);
    
    // Check the availability of symbols
    if(!SymbolSelect(Symbol1, true) || !SymbolSelect(Symbol2, true))
    {
        Print("Error: One or both symbols not available for trading!");
        return INIT_FAILED;
    }
    
    // Initialization of internal parameters
    CurrentZScorePeriod = ZScorePeriod;
    CurrentEntryThreshold = EntryThreshold;
    CurrentExitThreshold = ExitThreshold;
    
    // Initialization of arrays
    ArrayResize(prices1, CurrentZScorePeriod);
    ArrayResize(prices2, CurrentZScorePeriod);
    ArrayResize(ratio, CurrentZScorePeriod);
    ArrayResize(zscore, CurrentZScorePeriod);
    ArrayResize(correlationHistory, CorrelationPeriod);
    ArrayResize(posTickets, 0);
    
    // Initial calculation of correlations
    UpdateCorrelationHistory();
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Clear optimization results
    optimizationResults.Clear();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check the spread of both symbols
    double spread1 = SymbolInfoInteger(Symbol1, SYMBOL_SPREAD);
    double spread2 = SymbolInfoInteger(Symbol2, SYMBOL_SPREAD);
    
    if(spread1 > SpreadLimit || spread2 > SpreadLimit)
    {
        Print("Spread too wide: ", Symbol1, "=", spread1, ", ", Symbol2, "=", spread2);
        return;
    }
    
    // Update historical data
    UpdatePriceData();
    
    // Update correlation history
    UpdateCorrelationHistory();
    
    // Auto optimization
    if(AutoOptimize && ++tickCount >= OptimizationPeriod)
    {
        Optimize();
        tickCount = 0;
    }
    
    // Calculate the price ratio and Z-score
    CalculateRatioAndZScore();
    
    // Check the current status of positions
    UpdatePositionStatus();
    
    // Manage trading positions
    ManagePositions();
}

//+------------------------------------------------------------------+
//| Update correlation history                                       |
//+------------------------------------------------------------------+
void UpdateCorrelationHistory()
{
    // Shift the correlation history
    for(int i = CorrelationPeriod-1; i > 0; i--)
    {
        correlationHistory[i] = correlationHistory[i-1];
    }
    
    // Add a new correlation
    correlationHistory[0] = CalculateCurrentCorrelation();
}

//+------------------------------------------------------------------+
//| Find minimum correlation in history                              |
//+------------------------------------------------------------------+
double GetMinimumCorrelation()
{
    double minCorr = 1.0;
    for(int i = 0; i < CorrelationPeriod; i++)
    {
        if(correlationHistory[i] < minCorr)
            minCorr = correlationHistory[i];
    }
    return minCorr;
}

//+------------------------------------------------------------------+
//| Update price data for both symbols                               |
//+------------------------------------------------------------------+
void UpdatePriceData()
{
    for(int i = CurrentZScorePeriod-1; i > 0; i--)
    {
        prices1[i] = prices1[i-1];
        prices2[i] = prices2[i-1];
    }
    
    prices1[0] = SymbolInfoDouble(Symbol1, SYMBOL_BID);
    prices2[0] = SymbolInfoDouble(Symbol2, SYMBOL_BID);
}

//+------------------------------------------------------------------+
//| Calculate price ratio and Z-score                                |
//+------------------------------------------------------------------+
void CalculateRatioAndZScore()
{
    // Calculate price ratio
    for(int i = 0; i < CurrentZScorePeriod; i++)
    {
        if(prices2[i] == 0) continue;
        ratio[i] = prices1[i] / prices2[i];
    }
    
    // Calculate Z-score
    double mean = 0, stdDev = 0;
    
    // Calculate the average
    for(int i = 0; i < CurrentZScorePeriod; i++)
    {
        mean += ratio[i];
    }
    mean /= CurrentZScorePeriod;
    
    // Calculation of standard deviation
    for(int i = 0; i < CurrentZScorePeriod; i++)
    {
        stdDev += MathPow(ratio[i] - mean, 2);
    }
    stdDev = MathSqrt(stdDev / CurrentZScorePeriod);
    
    // Calculate Z-score
    for(int i = 0; i < CurrentZScorePeriod; i++)
    {
        if(stdDev == 0)
            zscore[i] = 0;
        else
            zscore[i] = (ratio[i] - mean) / stdDev;
    }
}

//+------------------------------------------------------------------+
//| Update position status                                           |
//+------------------------------------------------------------------+
void UpdatePositionStatus()
{
    // Clear the array of tickets
    ArrayResize(posTickets, 0);
    
    // Check all positions with our magic number
    int total = PositionsTotal();
    for(int i = 0; i < total; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
               (PositionGetString(POSITION_SYMBOL) == Symbol1 ||
                PositionGetString(POSITION_SYMBOL) == Symbol2))
            {
                int size = ArraySize(posTickets);
                ArrayResize(posTickets, size + 1);
                posTickets[size] = ticket;
            }
        }
    }
    
    isPositionOpen = (ArraySize(posTickets) > 0);
}

//+------------------------------------------------------------------+
//| Calculate total profit from all open positions                   |
//+------------------------------------------------------------------+
double CalculateTotalProfit()
{
    double totalProfit = 0;
    
    for(int i = 0; i < ArraySize(posTickets); i++)
    {
        if(!PositionSelectByTicket(posTickets[i])) continue;
        
        totalProfit += PositionGetDouble(POSITION_PROFIT);
    }
    
    return totalProfit;
}

//+------------------------------------------------------------------+
//| Manage trading positions based on Z-score and correlation        |
//+------------------------------------------------------------------+
void ManagePositions()
{
    // Current Z-score value
    double currentZScore = zscore[0];
    
    // If there are open positions, check the close condition
    if(isPositionOpen)
    {
        double totalProfit = CalculateTotalProfit();
        
        // Close positions if target profit is reached
        if(totalProfit >= ProfitTarget)
        {
            CloseAllPositions();
            isPositionOpen = false;
            
            // Reset the loss counter, since we closed with profit
            consecutiveLosses = 0;
        }
    }
    
    // Logic for averaging positions when correlation drops
    if(isPositionOpen && EnableAveraging)
    {
        double currentCorrelation = correlationHistory[0];
        
        // Check for a drop in correlation from the moment a position is opened
        if(averagingCount == 0)
        {
            // If this is the first check after opening a position, remember the initial correlation
            initialCorrelation = currentCorrelation;
            averagingCount++;
        }
        else if(initialCorrelation - currentCorrelation > CorrelationDropThreshold)
        {
            // If the correlation has fallen below the threshold, we add an averaging counter trade
            double averagingLot = lastLotSize * AveragingLotMultiplier;
            
            // Check the type of our current positions
            ENUM_POSITION_TYPE posType1 = POSITION_TYPE_BUY;
            string posSymbol = "";
            bool foundPos1 = false, foundPos2 = false;
            ENUM_POSITION_TYPE posType2 = POSITION_TYPE_BUY;
            
            for(int i = 0; i < ArraySize(posTickets); i++)
            {
                if(PositionSelectByTicket(posTickets[i]))
                {
                    string symbol = PositionGetString(POSITION_SYMBOL);
                    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                    
                    if(symbol == Symbol1)
                    {
                        posType1 = type;
                        foundPos1 = true;
                    }
                    else if(symbol == Symbol2)
                    {
                        posType2 = type;
                        foundPos2 = true;
                    }
                    
                    if(foundPos1 && foundPos2) break;
                }
            }
            
            if(foundPos1 && foundPos2)
            {
                // Open counter trades with an increased lot
                ENUM_POSITION_TYPE reverseType1 = (posType1 == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
                ENUM_POSITION_TYPE reverseType2 = (posType2 == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
                
                if(OpenPairPosition(reverseType1, Symbol1, reverseType2, Symbol2, averagingLot))
                {
                    Log("Averaging counter position opened: " + 
                        (reverseType1 == POSITION_TYPE_BUY ? "BUY " : "SELL ") + Symbol1 + ", " +
                        (reverseType2 == POSITION_TYPE_BUY ? "BUY " : "SELL ") + Symbol2 + 
                        ", Correlation drop: " + DoubleToString(initialCorrelation - currentCorrelation, 4) +
                        (EnableProtectiveStops ? ", Protective stop: " + IntegerToString(ProtectiveStopPips) + " pips" : "") +
                        (EnableTakeProfit ? ", Take profit: " + IntegerToString(TakeProfitPips) + " pips" : ""));
                    
                    // Update the initial correlation for the next check
                    initialCorrelation = currentCorrelation;
                    averagingCount++;
                }
            }
        }
    }
    
    // The logic for opening new positions is to enter when the correlation is at a minimum
    if(!isPositionOpen)
    {
        double currentCorrelation = correlationHistory[0];
        double minCorrelation = GetMinimumCorrelation();
        
        // If the current correlation is close to the minimum one (with a small tolerance)
        if(MathAbs(currentCorrelation - minCorrelation) < 0.01 && MathAbs(currentZScore) >= CurrentEntryThreshold)
        {
            // Calculate lot size based on risk
            double riskLot = CalculatePositionSize();
            lastLotSize = riskLot; // Save the lot size for averaging
            averagingCount = 0; // Reset the averaging counter
            
            if(currentZScore > 0) // Symbol1 is overvalued, Symbol2 is undervalue
            {
                // Sell Symbol1 and buy Symbol2
                if(OpenPairPosition(POSITION_TYPE_SELL, Symbol1, POSITION_TYPE_BUY, Symbol2, riskLot))
                {
                    Log("Paired position opened: SELL " + Symbol1 + ", BUY " + Symbol2 + 
                        ", Z-score: " + DoubleToString(currentZScore, 2) +
                        ", Correlation: " + DoubleToString(currentCorrelation, 4) +
                        " (min: " + DoubleToString(minCorrelation, 4) + ")");
                    isPositionOpen = true;
                    initialCorrelation = currentCorrelation; // Remember the initial correlation
                }
            }
            else // Symbol1 is undervalued, Symbol2 is overvalued
            {
                // Buy Symbol1 and sell Symbol2
                if(OpenPairPosition(POSITION_TYPE_BUY, Symbol1, POSITION_TYPE_SELL, Symbol2, riskLot))
                {
                    Log("Paired position opened: BUY " + Symbol1 + ", SELL " + Symbol2 + 
                        ", Z-score: " + DoubleToString(currentZScore, 2) +
                        ", Correlation: " + DoubleToString(currentCorrelation, 4) +
                        " (min: " + DoubleToString(minCorrelation, 4) + ")");
                    isPositionOpen = true;
                    initialCorrelation = currentCorrelation; // Remember the initial correlation
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check if there are open positions for a symbol                   |
//+------------------------------------------------------------------+
bool HasOpenPositions(string symbol)
{
    for(int i = 0; i < ArraySize(posTickets); i++)
    {
        if(!PositionSelectByTicket(posTickets[i])) continue;
        
        if(PositionGetString(POSITION_SYMBOL) == symbol &&
           PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Close all open positions for both symbols                        |
//+------------------------------------------------------------------+
void CloseAllPositions()
{
    double totalProfit = 0;
    
    // Close all items from the ticket array
    for(int i = ArraySize(posTickets) - 1; i >= 0; i--)
    {
        if(!PositionSelectByTicket(posTickets[i])) continue;
        
        totalProfit += PositionGetDouble(POSITION_PROFIT);
        trade.PositionClose(posTickets[i]);
    }
    
    // Clear the array of tickets
    ArrayResize(posTickets, 0);
    
    lastTradeProfit = totalProfit;
    
    if(totalProfit < 0)
        consecutiveLosses++;
    else
        consecutiveLosses = 0;
        
    // Reset the averaging counter and the initial correlation
    averagingCount = 0;
    initialCorrelation = 0.0;
    lastLotSize = 0.0;
    
    Log("All positions closed. Total profit: " + DoubleToString(totalProfit, 2) + 
        ", Consecutive losses: " + IntegerToString(consecutiveLosses));
}

//+------------------------------------------------------------------+
//| Add position ticket to array                                     |
//+------------------------------------------------------------------+
void AddPositionTicket(ulong ticket)
{
    int size = ArraySize(posTickets);
    ArrayResize(posTickets, size + 1);
    posTickets[size] = ticket;
}

//+------------------------------------------------------------------+
//| Open a pair position with specified types and lots               |
//+------------------------------------------------------------------+
bool OpenPairPosition(ENUM_POSITION_TYPE type1, string symbol1, 
                     ENUM_POSITION_TYPE type2, string symbol2, 
                     double lotSize)
{
    bool success1 = false, success2 = false;
    ulong ticket1 = 0, ticket2 = 0;
    
    // Calculate protective stop losses and take profits, if enabled
    double sl1 = 0, sl2 = 0, tp1 = 0, tp2 = 0;
    double point1 = SymbolInfoDouble(symbol1, SYMBOL_POINT);
    double point2 = SymbolInfoDouble(symbol2, SYMBOL_POINT);
    
    if(EnableProtectiveStops)
    {
        if(type1 == POSITION_TYPE_BUY)
        {
            double ask1 = SymbolInfoDouble(symbol1, SYMBOL_ASK);
            sl1 = ask1 - ProtectiveStopPips * point1;
        }
        else
        {
            double bid1 = SymbolInfoDouble(symbol1, SYMBOL_BID);
            sl1 = bid1 + ProtectiveStopPips * point1;
        }
        
        if(type2 == POSITION_TYPE_BUY)
        {
            double ask2 = SymbolInfoDouble(symbol2, SYMBOL_ASK);
            sl2 = ask2 - ProtectiveStopPips * point2;
        }
        else
        {
            double bid2 = SymbolInfoDouble(symbol2, SYMBOL_BID);
            sl2 = bid2 + ProtectiveStopPips * point2;
        }
    }
    
    // Take profit calculation
    if(EnableTakeProfit)
    {
        if(type1 == POSITION_TYPE_BUY)
        {
            double ask1 = SymbolInfoDouble(symbol1, SYMBOL_ASK);
            tp1 = ask1 + TakeProfitPips * point1;
        }
        else
        {
            double bid1 = SymbolInfoDouble(symbol1, SYMBOL_BID);
            tp1 = bid1 - TakeProfitPips * point1;
        }
        
        if(type2 == POSITION_TYPE_BUY)
        {
            double ask2 = SymbolInfoDouble(symbol2, SYMBOL_ASK);
            tp2 = ask2 + TakeProfitPips * point2;
        }
        else
        {
            double bid2 = SymbolInfoDouble(symbol2, SYMBOL_BID);
            tp2 = bid2 - TakeProfitPips * point2;
        }
    }
    
    if(type1 == POSITION_TYPE_BUY)
    {
        double ask1 = SymbolInfoDouble(symbol1, SYMBOL_ASK);
        success1 = trade.Buy(lotSize, symbol1, ask1, sl1, tp1);
        if(success1) ticket1 = trade.ResultOrder();
    }
    else
    {
        double bid1 = SymbolInfoDouble(symbol1, SYMBOL_BID);
        success1 = trade.Sell(lotSize, symbol1, bid1, sl1, tp1);
        if(success1) ticket1 = trade.ResultOrder();
    }
    
    if(success1)
    {
        if(type2 == POSITION_TYPE_BUY)
        {
            double ask2 = SymbolInfoDouble(symbol2, SYMBOL_ASK);
            success2 = trade.Buy(lotSize, symbol2, ask2, sl2, tp2);
            if(success2) ticket2 = trade.ResultOrder();
        }
        else
        {
            double bid2 = SymbolInfoDouble(symbol2, SYMBOL_BID);
            success2 = trade.Sell(lotSize, symbol2, bid2, sl2, tp2);
            if(success2) ticket2 = trade.ResultOrder();
        }
        
        // If the second part of the pair fails, close the first one
        if(!success2)
        {
            trade.PositionClose(ticket1);
            return false;
        }
        else
        {
            // Add tickets to the array
            AddPositionTicket(ticket1);
            AddPositionTicket(ticket2);
        }
    }
    
    return success1 && success2;
}

//+------------------------------------------------------------------+
//| Calculate current correlation                                    |
//+------------------------------------------------------------------+
double CalculateCurrentCorrelation()
{
    double close1[], close2[];
    ArrayResize(close1, 100);
    ArrayResize(close2, 100);
    
    if(CopyClose(Symbol1, PERIOD_CURRENT, 0, 100, close1) != 100) return 0;
    if(CopyClose(Symbol2, PERIOD_CURRENT, 0, 100, close2) != 100) return 0;
    
    return CalculateCorrelation(close1, close2, 100);
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk percentage                 |
//+------------------------------------------------------------------+
double CalculatePositionSize()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * RiskPercent / 100.0;
    
    double tickValue1 = SymbolInfoDouble(Symbol1, SYMBOL_TRADE_TICK_VALUE);
    double tickSize1 = SymbolInfoDouble(Symbol1, SYMBOL_TRADE_TICK_SIZE);
    double point1 = SymbolInfoDouble(Symbol1, SYMBOL_POINT);
    
    double lotStep = SymbolInfoDouble(Symbol1, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(Symbol1, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(Symbol1, SYMBOL_VOLUME_MAX);
    
    // Risk-based lot calculation (using an approximate stop loss of 100 pips for calculation)
    double virtualStopLoss = 100;
    double riskPerPoint = tickValue1 * (point1 / tickSize1);
    double lotSizeByRisk = riskAmount / (virtualStopLoss * riskPerPoint);
    
    // Round to the nearest lot step
    lotSizeByRisk = MathFloor(lotSizeByRisk / lotStep) * lotStep;
    
    // Check for minimum and maximum lot size
    lotSizeByRisk = MathMax(minLot, MathMin(maxLot, lotSizeByRisk));
    
    return lotSizeByRisk;
}

//+------------------------------------------------------------------+
//| Optimization function                                            |
//+------------------------------------------------------------------+
void Optimize()
{
    Print("Starting optimization...");
    
    optimizationResults.Clear();
    
    // Optimization ranges
    int zScorePeriodMin = 50, zScorePeriodMax = 200, zScorePeriodStep = 25;
    double entryThresholdMin = 1.5, entryThresholdMax = 3.0, entryThresholdStep = 0.25;
    double exitThresholdMin = 0.0, exitThresholdMax = 1.0, exitThresholdStep = 0.25;
    
    // Iterate over all combinations of parameters
    for(int period = zScorePeriodMin; period <= zScorePeriodMax; period += zScorePeriodStep)
    {
        for(double entry = entryThresholdMin; entry <= entryThresholdMax; entry += entryThresholdStep)
        {
            for(double exit = exitThresholdMin; exit <= exitThresholdMax; exit += exitThresholdStep)
            {
                // Test parameters
                double profit = TestParameters(period, entry, exit);
                
                OptimizationResult* result = new OptimizationResult();
                result.zScorePeriod = period;
                result.entryThreshold = entry;
                result.exitThreshold = exit;
                result.profit = profit;
                
                optimizationResults.Add(result);
            }
        }
    }
    
    // Search for the best result
    OptimizationResult* bestResult = NULL;
    for(int i = 0; i < optimizationResults.Total(); i++)
    {
        OptimizationResult* currentResult = optimizationResults.At(i);
        if(bestResult == NULL || currentResult.profit > bestResult.profit)
        {
            bestResult = currentResult;
        }
    }
    
    if(bestResult != NULL)
    {
        // Update the EA internal parameters
        CurrentZScorePeriod = bestResult.zScorePeriod;
        CurrentEntryThreshold = bestResult.entryThreshold;
        CurrentExitThreshold = bestResult.exitThreshold;
        
        // Update arrays
        ArrayResize(prices1, CurrentZScorePeriod);
        ArrayResize(prices2, CurrentZScorePeriod);
        ArrayResize(ratio, CurrentZScorePeriod);
        ArrayResize(zscore, CurrentZScorePeriod);
        
        Print("Optimization complete. New parameters: ZScorePeriod = ", CurrentZScorePeriod, 
              ", EntryThreshold = ", CurrentEntryThreshold, ", ExitThreshold = ", CurrentExitThreshold);
    }
    else
    {
        Print("Optimization could not find better parameters.");
    }
}

//+------------------------------------------------------------------+
//| Test a set of parameters                                         |
//+------------------------------------------------------------------+
double TestParameters(int period, double entry, double exit)
{
    double test_prices1[], test_prices2[], test_ratio[], test_zscore[];
    ArrayResize(test_prices1, period);
    ArrayResize(test_prices2, period);
    ArrayResize(test_ratio, period);
    ArrayResize(test_zscore, period);
    
    double close1[], close2[];
    ArraySetAsSeries(close1, true);
    ArraySetAsSeries(close2, true);
    
    int copied1 = CopyClose(Symbol1, PERIOD_CURRENT, 0, MinDataPoints, close1);
    int copied2 = CopyClose(Symbol2, PERIOD_CURRENT, 0, MinDataPoints, close2);
    
    if(copied1 < MinDataPoints || copied2 < MinDataPoints)
    {
        Print("Not enough data for testing");
        return -DBL_MAX;
    }
    
    double profit = 0;
    bool inPosition = false;
    double entryPrice1 = 0, entryPrice2 = 0;
    ENUM_POSITION_TYPE posType1 = POSITION_TYPE_BUY, posType2 = POSITION_TYPE_BUY;
    
    // Create a correlation history for testing
    double testCorrelations[];
    ArrayResize(testCorrelations, CorrelationPeriod);
    
    // Fill in the initial data
    for(int i = 0; i < period; i++)
    {
        test_prices1[i] = close1[MinDataPoints - 1 - i];
        test_prices2[i] = close2[MinDataPoints - 1 - i];
    }
    
    // Fill in the initial correlations
    double corrWindow = 50; // Window for calculating correlation
    
    // Inverse simulation
    for(int i = period; i < MinDataPoints; i++)
    {
        // Shift data
        for(int j = period-1; j > 0; j--)
        {
            test_prices1[j] = test_prices1[j-1];
            test_prices2[j] = test_prices2[j-1];
        }
        
        test_prices1[0] = close1[MinDataPoints - 1 - i];
        test_prices2[0] = close2[MinDataPoints - 1 - i];
        
        // Calculate correlation
        double corrData1[50], corrData2[50];
        for(int j = 0; j < 50; j++)
        {
            if(i >= j+50)
            {
                corrData1[j] = close1[MinDataPoints - 1 - i + j];
                corrData2[j] = close2[MinDataPoints - 1 - i + j];
            }
            else
            {
                corrData1[j] = close1[0];
                corrData2[j] = close2[0];
            }
        }
        double currentCorr = CalculateCorrelation(corrData1, corrData2, 50);
        
        // Shift in correlation history
        for(int j = CorrelationPeriod-1; j > 0; j--)
        {
            testCorrelations[j] = testCorrelations[j-1];
        }
        testCorrelations[0] = currentCorr;
        
        // Calculate the ratio
        for(int j = 0; j < period; j++)
        {
            if(test_prices2[j] == 0) continue;
            test_ratio[j] = test_prices1[j] / test_prices2[j];
        }
        
        // Calculate Z-score
        double mean = 0, stdDev = 0;
        
        for(int j = 0; j < period; j++)
        {
            mean += test_ratio[j];
        }
        mean /= period;
        
        for(int j = 0; j < period; j++)
        {
            stdDev += MathPow(test_ratio[j] - mean, 2);
        }
        stdDev = MathSqrt(stdDev / period);
        
        for(int j = 0; j < period; j++)
        {
            if(stdDev == 0)
                test_zscore[j] = 0;
            else
                test_zscore[j] = (test_ratio[j] - mean) / stdDev;
        }
        
        double currentZScore = test_zscore[0];
        
        // Position close logic - close if the profit of USD 1 is reached
        if(inPosition)
        {
            double currentProfit = 0;
            
            if(posType1 == POSITION_TYPE_BUY)
                currentProfit += (close1[MinDataPoints - 1 - i] - entryPrice1) * 10000;
            else
                currentProfit += (entryPrice1 - close1[MinDataPoints - 1 - i]) * 10000;
                
            if(posType2 == POSITION_TYPE_BUY)
                currentProfit += (close2[MinDataPoints - 1 - i] - entryPrice2) * 10000;
            else
                currentProfit += (entryPrice2 - close2[MinDataPoints - 1 - i]) * 10000;
                
            if(currentProfit >= ProfitTarget)
            {
                profit += currentProfit;
                inPosition = false;
            }
        }
        
        // Logic for opening new positions - check the minimum correlation
        if(!inPosition && i > CorrelationPeriod)
        {
            // Find the minimum correlation in history
            double minCorr = 1.0;
            for(int j = 0; j < CorrelationPeriod; j++)
            {
                if(testCorrelations[j] < minCorr)
                    minCorr = testCorrelations[j];
            }
            
            // If the current correlation is close to the minimum
            if(MathAbs(testCorrelations[0] - minCorr) < 0.01 && MathAbs(currentZScore) >= entry)
            {
                if(currentZScore > 0) // Symbol1 is overvalued, Symbol2 is undervalue
                {
                    posType1 = POSITION_TYPE_SELL;
                    posType2 = POSITION_TYPE_BUY;
                }
                else // Symbol1 is undervalued, Symbol2 is overvalued
                {
                    posType1 = POSITION_TYPE_BUY;
                    posType2 = POSITION_TYPE_SELL;
                }
                
                entryPrice1 = close1[MinDataPoints - 1 - i];
                entryPrice2 = close2[MinDataPoints - 1 - i];
                inPosition = true;
                
                // To test averaging, we remember the initial correlation
                double testInitialCorr = testCorrelations[0];
                double testLastLot = 0.01; // Initial test lot
                int testAveragingCount = 0;
                
                // Simulate possible averaging in future bars
                for(int k = i+1; k < i+50 && k < MinDataPoints && inPosition; k++)
                {
                    double futureCorrVal = 0;
                    if(k < MinDataPoints)
                    {
                        // Calculate future correlation (approximate)
                        double futureCorr1[50], futureCorr2[50];
                        for(int j = 0; j < 50; j++)
                        {
                            if(k >= j+50)
                            {
                                futureCorr1[j] = close1[MinDataPoints - 1 - k + j];
                                futureCorr2[j] = close2[MinDataPoints - 1 - k + j];
                            }
                            else
                            {
                                futureCorr1[j] = close1[0];
                                futureCorr2[j] = close2[0];
                            }
                        }
                        futureCorrVal = CalculateCorrelation(futureCorr1, futureCorr2, 50);
                        
                        // Check for a drop in correlation
                        if(testInitialCorr - futureCorrVal > CorrelationDropThreshold && EnableAveraging)
                        {
                            // Position averaging
                            double averagingLot = testLastLot * AveragingLotMultiplier;
                            
                            // Simulate counter trades
                            ENUM_POSITION_TYPE revType1 = (posType1 == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
                            ENUM_POSITION_TYPE revType2 = (posType2 == POSITION_TYPE_BUY) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
                            
                            // Calculate the impact on overall profit
                            double entryPriceAv1 = close1[MinDataPoints - 1 - k];
                            double entryPriceAv2 = close2[MinDataPoints - 1 - k];
                            
                            // Update parameters for the next check
                            testInitialCorr = futureCorrVal;
                            testLastLot = averagingLot;
                            testAveragingCount++;
                        }
                    }
                }
            }
        }
    }
    
    // Close the last position if it remains open
    if(inPosition)
    {
        double currentPrice1 = close1[0];
        double currentPrice2 = close2[0];
        
        if(posType1 == POSITION_TYPE_BUY)
            profit += currentPrice1 - entryPrice1;
        else
            profit += entryPrice1 - currentPrice1;
            
        if(posType2 == POSITION_TYPE_BUY)
            profit += currentPrice2 - entryPrice2;
        else
            profit += entryPrice2 - currentPrice2;
    }
    
    return profit;
}

//+------------------------------------------------------------------+
//| Custom function to calculate correlation between two arrays      |
//+------------------------------------------------------------------+
double CalculateCorrelation(const double &array1[], const double &array2[], const int size)
{
    if(size <= 1) return 0;
    
    double sum_x = 0, sum_y = 0, sum_xy = 0;
    double sum_x2 = 0, sum_y2 = 0;
    
    for(int i = 0; i < size; i++)
    {
        sum_x += array1[i];
        sum_y += array2[i];
        sum_xy += array1[i] * array2[i];
        sum_x2 += array1[i] * array1[i];
        sum_y2 += array2[i] * array2[i];
    }
    
    double denominator = MathSqrt((size * sum_x2 - sum_x * sum_x) * (size * sum_y2 - sum_y * sum_y));
    
    if(denominator == 0) return 0;
    
    return (size * sum_xy - sum_x * sum_y) / denominator;
}

//+------------------------------------------------------------------+
//| Function to log important events                                 |
//+------------------------------------------------------------------+
void Log(string message)
{
    Print(TimeToString(TimeCurrent()) + ": " + message);
    
    int handle = FileOpen("PairTrading_Log.txt", FILE_WRITE|FILE_READ|FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        FileSeek(handle, 0, SEEK_END);
        FileWriteString(handle, TimeToString(TimeCurrent()) + ": " + message + "\n");
        FileClose(handle);
    }
}
