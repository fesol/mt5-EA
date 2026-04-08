#include <Trade\Trade.mqh>

CPositionInfo  posinfo;
CTrade         trade;
COrderInfo     ordinfo;

enum LotTyp { Lot_per_1k_Capital = 0, Fixed_Lot_Size = 1 };

double ustec10ma, ustec20ma;
double current_balance, current_equity, current_profit_pcnt;

input int    stoploss_candles_low = 3;
input double TPfactor            = 1.0;
input bool   allowsells          = false;
input double profit_pcnt_closeall = 6.0;

input double VolumeMAmultiplier = 1.5;
input int    VolumeMAperiod     = 20;

input uint   InpPeriodAMAperiod    = 5;
input uint   InpPeriodAMAfast      = 3;
input uint   InpPeriodAMAslow      = 8;

input uint   InpPeriodAMAperiod_2  = 8;
input uint   InpPeriodAMAfast_2    = 5;
input uint   InpPeriodAMAslow_2    = 21;

input ENUM_TIMEFRAMES InptUSTECtrendfilderTimeframe = PERIOD_D1;

input int    InpNumberCandlesEMAabove = 20;

input int    InpStochDPeriod   = 3;
input int    InpStochPeriod    = 14;
input int    stoch_level_buy   = 20;
input int    stoch_level_sell  = 80;
input int    Second_crose_MaxCandles = 13;

input int                  BollPeriod            = 20;
input int                  BollShift             = 1;
input double               BollDev               = 3.0;
input ENUM_APPLIED_PRICE   BollApPrice           = PRICE_MEDIAN;
input int                  MaxCandlesBollLookback = 10;

input int    ATR_Period     = 14;
input double ATR_Multiplier = 1.0;

input group "=== EA specific Variables ==="
input ulong  InpMagic        = 44444;

input double RiskPercent     = 1.0;
input int    BarsSince       = 3;
input int    BarsMaxOpen     = 15;
input int    MaxTrades       = 1;
input int    MinBarsData     = 100;

input bool   UseUstecPerformanceFilter = true;
input int    periodBars      = 20;
input double Performancethreshold = 1.0;

input group "=== Trade Management ==="
input LotTyp Lot_Type       = Lot_per_1k_Capital;
input double Lotsize        = 0.02;
input double Lotsizeper1000 = 0.01;
input int    MaxSpread      = 15;
input int    Max_positions  = 1;

input ENUM_APPLIED_PRICE AppPrice = PRICE_MEDIAN;

int handle_stockAD[];
int handle_Bollinger[];
int handle_iATRs[];
int handle_AMA1ustec = INVALID_HANDLE;
int handle_AMA2ustec = INVALID_HANDLE;

string TradableSymbols[];

string nasdaqSymbols[] = {
"AZO.NYSE","BKNG.NAS","MKL.NYSE","MPWR.NAS","IT.NYSE","MELI.NAS","HUBS.NYSE","IDXX.NAS",
"GS.NYSE","UNH.NYSE","MCK.NYSE","CW.NYSE","ALNY.NAS","EME.NYSE","GHC.NYSE","RH.NYSE",
"STRL.NAS","SPOT.NYSE","LULU.NAS","FDS.NYSE","ULTA.NAS","AVGO.NAS","IDCC.NAS","LITE.NAS",
"CYBR.NAS","STX.NAS","CRWD.NAS","MOH.NYSE","CASY.NAS","EQIX.NAS","WSO.NYSE","CHE.NYSE",
"GWW.NYSE","ADBE.NAS","AVAV.NAS","MUSA.NYSE","PWR.NYSE","HCA.NYSE","ERIE.NYSE","RL.NYSE",
"MU.NAS","ACN.NYSE","MORN.NAS","NET.NYSE","TYL.NYSE","BLK.NYSE","HII.NYSE","QQQ.NAS",
"LII.NYSE","CMI.NYSE","CIEN.NYSE","SITM.NAS","AXON.NAS","ROK.NYSE","MTD.NYSE","NOC.NYSE",
"ZBRA.NAS","MNDY.NAS","ZS.NAS","GOOG.NAS","TEAM.NAS","SNOW.NYSE","HWM.NYSE","AMD.NAS",
"POOL.NAS","LLY.NYSE","JBL.NAS","TEL.NYSE","SAM.NYSE","ORCL.NYSE","STZ.NYSE","AEM.NYSE",
"UTHR.NAS","CRM.NYSE","MDB.NAS","MTZ.NYSE","NRG.NYSE","MLM.NYSE","AMG.NYSE","HEI.NYSE",
"ALGN.NAS","FIVE.NAS","SOXX.NAS","MKTX.NAS","TFX.NYSE","JPM.NYSE","CAR.NAS","SANM.NAS",
"TTWO.NAS","EXPE.NAS","GD.NYSE","CAH.NYSE","VRSN.NAS","FSLR.NYSE","IBP.NYSE","TDY.NYSE",
"THC.NYSE","BABA.NYSE","PODD.NAS","INTU.NAS","MSTR.NAS","GDDY.NYSE","NTES.NAS","ODFL.NAS",
"KTOS.NAS","WCC.NYSE","NVDA.NAS","BA.NYSE","EPAM.NYSE","AMAT.NAS","MSI.NYSE","TPR.NYSE",
"W.NYSE","GDXJ.NYSE","CLX.NYSE","RTX.NYSE","VEEV.NAS","WELL.NYSE","CDNS.NAS","BOOT.NYSE",
"AU.NYSE","BLDR.NAS","JLL.NYSE","VST.NYSE","SE.NYSE","EA.NAS","VRSK.NAS","ONTO.NYSE",
"NICE.NAS","GKOS.NYSE","NTRA.NAS","IEX.NYSE","AYI.NYSE","TGT.NYSE","NEM.NYSE","BDX.NYSE",
"ANF.NYSE","TER.NAS","PCTY.NAS","VRTX.NAS","TSEM.NAS","DLTR.NAS","DE.NYSE","WST.NYSE",
"AN.NYSE","LECO.NAS","AVB.NYSE","JNJ.NYSE","MPC.NYSE","ZTS.NYSE","ATI.NYSE","ABBV.NYSE",
"AMR.NYSE","MS.NYSE","CCJ.NYSE","PSA.NYSE","GDX.NYSE","CME.NAS","DG.NYSE","SIMO.NAS",
"UPS.NYSE","GWRE.NYSE","ANET.NYSE","WYNN.NAS","ADI.NAS","SIL.NYSE","GLW.NYSE","CDW.NAS",
"AXSM.NAS","MKSI.NAS","JCI.NYSE","NXST.NAS","ESS.NYSE","AER.NYSE","LH.NYSE","LAD.NYSE",
"STE.NYSE","DVA.NYSE","ALLE.NYSE","C.NYSE","MRCY.NAS","ORA.NYSE","EFX.NYSE","MSCI.NYSE",
"COST.NAS","BIDU.NAS","BK.NYSE","AAPL.NAS","MSFT.NAS","AMZN.NAS","META.NAS","NOW.NYSE",
"PANW.NAS","LRCX.NAS","KLAC.NAS","TSM.NAS"
};

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   TesterHideIndicators(true);

   if(!SymbolSelect("USTEC", true))
   {
      Print("ERROR: Unable to select USTEC symbol");
      return INIT_FAILED;
   }

   handle_AMA1ustec = iAMA("USTEC", InptUSTECtrendfilderTimeframe, InpPeriodAMAperiod, InpPeriodAMAfast, InpPeriodAMAslow, 0, PRICE_CLOSE);
   handle_AMA2ustec = iAMA("USTEC", InptUSTECtrendfilderTimeframe, InpPeriodAMAperiod_2, InpPeriodAMAfast_2, InpPeriodAMAslow_2, 0, PRICE_CLOSE);

   if(handle_AMA1ustec == INVALID_HANDLE || handle_AMA2ustec == INVALID_HANDLE)
   {
      Print("ERROR: failed to get USTEC AMA handlers");
      return INIT_FAILED;
   }

   int symbolsTotal = ArraySize(nasdaqSymbols);
   string filteredSymbols[];
   int filteredCount = 0;

   for(int i = 0; i < symbolsTotal; i++)
   {
      string symbolName = nasdaqSymbols[i];
      if(StringLen(symbolName) == 0) continue;

      if(SymbolInfoInteger(symbolName, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
         continue;

      if(!SymbolInfoInteger(symbolName, SYMBOL_VISIBLE))
      {
         if(!SymbolSelect(symbolName, true))
         {
            continue;
         }
      }

      if(Bars(symbolName, PERIOD_CURRENT) < MinBarsData)
         continue;

      int handleBB = iBands(symbolName, PERIOD_CURRENT, BollPeriod, BollShift, BollDev, BollApPrice);
      int handleStochAD = iCustom(symbolName, PERIOD_CURRENT, "stochastic_AD", InpStochPeriod, InpStochDPeriod, VOLUME_TICK);
      int handleATR = iATR(symbolName, PERIOD_CURRENT, ATR_Period);

      bool ok = (handleBB != INVALID_HANDLE && handleStochAD != INVALID_HANDLE && handleATR != INVALID_HANDLE);

      if(handleBB != INVALID_HANDLE) IndicatorRelease(handleBB);
      if(handleStochAD != INVALID_HANDLE) IndicatorRelease(handleStochAD);
      if(handleATR != INVALID_HANDLE) IndicatorRelease(handleATR);

      if(!ok)
         continue;

      ArrayResize(filteredSymbols, filteredCount + 1);
      filteredSymbols[filteredCount] = symbolName;
      filteredCount++;
   }

   if(filteredCount == 0)
   {
      Print("ERROR: No tradable symbols with sufficient data");
      return INIT_FAILED;
   }

   ArrayResize(TradableSymbols, filteredCount);
   ArrayCopy(TradableSymbols, filteredSymbols, 0, 0, WHOLE_ARRAY);

   ArrayResize(handle_stockAD, filteredCount);
   ArrayResize(handle_Bollinger, filteredCount);
   ArrayResize(handle_iATRs, filteredCount);

   for(int i = 0; i < filteredCount; i++)
   {
      handle_stockAD[i] = Get_handles_stockAD(TradableSymbols[i]);
      handle_Bollinger[i] = Get_handles_Bollinger(TradableSymbols[i]);
      handle_iATRs[i] = Get_handles_ATR(TradableSymbols[i]);

      if(handle_stockAD[i] == INVALID_HANDLE || handle_Bollinger[i] == INVALID_HANDLE || handle_iATRs[i] == INVALID_HANDLE)
      {
         PrintFormat("ERROR: Failed to create handles for %s", TradableSymbols[i]);
         return INIT_FAILED;
      }
   }

   PrintFormat("INIT_SUCCEEDED: loaded %d symbols", filteredCount);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   for(int i = 0; i < ArraySize(handle_stockAD); i++)
   {
      if(handle_stockAD[i] != INVALID_HANDLE)
         IndicatorRelease(handle_stockAD[i]);
      if(handle_Bollinger[i] != INVALID_HANDLE)
         IndicatorRelease(handle_Bollinger[i]);
      if(handle_iATRs[i] != INVALID_HANDLE)
         IndicatorRelease(handle_iATRs[i]);
   }

   if(handle_AMA1ustec != INVALID_HANDLE)
      IndicatorRelease(handle_AMA1ustec);
   if(handle_AMA2ustec != INVALID_HANDLE)
      IndicatorRelease(handle_AMA2ustec);
}

void OnTick()
{
   current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   current_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   current_profit_pcnt = ((current_equity - current_balance) / current_balance) * 100.0;

   if(current_profit_pcnt >= profit_pcnt_closeall)
      ClosePositions();

   if(!IsNewBar())
      return;

   ustec10ma = iAMAGet(handle_AMA1ustec, 0);
   ustec20ma = iAMAGet(handle_AMA2ustec, 0);

   for(int i = 0; i < ArraySize(TradableSymbols); i++)
      RunSymbols(TradableSymbols[i], i);
}

void RunSymbols(string symbol, int count)
{
   if(StringLen(symbol) == 0)
      return;

   if(!SymbolSelect(symbol, true))
      return;

   if(Bars(symbol, PERIOD_CURRENT) < MinBarsData)
      return;

   if(handle_stockAD[count] == INVALID_HANDLE || handle_Bollinger[count] == INVALID_HANDLE || handle_iATRs[count] == INVALID_HANDLE)
      return;

   if(UseUstecPerformanceFilter)
   {
      if(Bars(symbol, PERIOD_CURRENT) < periodBars + 2 || Bars("USTEC", PERIOD_CURRENT) < periodBars + 2)
         return;

      double stockPriceCurrent  = iClose(symbol, PERIOD_CURRENT, 1);
      double stockPricePrevious = iClose(symbol, PERIOD_CURRENT, periodBars + 1);
      double nqPriceCurrent     = iClose("USTEC", PERIOD_CURRENT, 1);
      double nqPricePrevious    = iClose("USTEC", PERIOD_CURRENT, periodBars + 1);

      if(stockPricePrevious <= 0.0 || nqPricePrevious <= 0.0)
         return;

      double stockPercentChange = (stockPriceCurrent - stockPricePrevious) / stockPricePrevious * 100.0;
      double nqPercentChange    = (nqPriceCurrent - nqPricePrevious) / nqPricePrevious * 100.0;
      double relativePerformance = stockPercentChange - nqPercentChange;

      if(relativePerformance < Performancethreshold)
         return;
   }

   double StochAD_1 = iStochADGet(handle_stockAD[count], 1);
   double StochAD_2 = iStochADGet(handle_stockAD[count], 2);
   double Bollinger_1 = iBollingerGet(handle_Bollinger[count], 1);

   if(StochAD_1 > stoch_level_buy && StochAD_2 < stoch_level_buy && recentCandleBelowBollinger(handle_Bollinger[count], symbol))
   {
      int BuyTotal = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         if(posinfo.SelectByIndex(i) && posinfo.PositionType() == POSITION_TYPE_BUY && posinfo.Symbol() == symbol && posinfo.Magic() == InpMagic)
            BuyTotal++;
      }

      if(BuyTotal >= Max_positions)
         return;

      double Ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double Bid = SymbolInfoDouble(symbol, SYMBOL_BID);

      if(Ask <= 0.0 || Bid <= 0.0)
         return;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return;

      double spreadPoints = (Ask - Bid) / point;
      if(MaxSpread > 0 && spreadPoints > MaxSpread)
         return;

      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      Ask = NormalizeDouble(Ask, digits);

      int low_index = iLowest(symbol, PERIOD_CURRENT, MODE_LOW, stoploss_candles_low, 1);
      double sl = iLow(symbol, PERIOD_CURRENT, low_index);
      if(sl <= 0.0)
         return;

      double ATR = iATRGet(handle_iATRs[count], 0);
      if(ATR > 0.0 && (Ask - sl) < ATR)
         sl = sl - (ATR * ATR_Multiplier);

      double tp = Ask + TPfactor * (Ask - sl);

      double vol;
      if(Lot_Type == Fixed_Lot_Size)
         vol = Lotsize;
      else
         vol = CalculateLotSize(symbol, Ask, sl);

      if(vol <= 0.0)
         return;

      bool result = trade.Buy(vol, symbol, Ask, sl, tp);
      if(!result)
         PrintFormat("Buy failed for %s, code=%d desc=%s", symbol, trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

bool IsNewBar()
{
   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(currentTime == 0)
      return false;

   if(previousTime != currentTime)
   {
      previousTime = currentTime;
      return true;
   }
   return false;
}

double CalculateLotSize(string symbol, double price, double sl)
{
   if(RiskPercent <= 0.0 || RiskPercent > 100.0)
      return 0.0;

   double SLDistance = MathAbs(price - sl);
   if(SLDistance <= 0.0)
      return 0.0;

   double accountRisk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100.0;

   double tickSize   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot     = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(tickSize <= 0.0 || tickValue <= 0.0 || volumeStep <= 0.0 || minLot <= 0.0 || maxLot <= 0.0)
      return 0.0;

   double valuePerLot = (SLDistance / tickSize) * tickValue;
   if(valuePerLot <= 0.0)
      return 0.0;

   double rawLots = accountRisk / valuePerLot;
   double lots = MathFloor(rawLots / volumeStep) * volumeStep;

   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;

   return lots;
}

void ClosePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(posinfo.SelectByIndex(i) && posinfo.Magic() == InpMagic)
      {
         trade.PositionClose(posinfo.Ticket());
         Sleep(100);
      }
   }
}

bool recentCandleBelowBollinger(int handle, string symbol)
{
   if(handle == INVALID_HANDLE || StringLen(symbol) == 0)
      return false;

   if(Bars(symbol, PERIOD_CURRENT) < MaxCandlesBollLookback + 2)
      return false;

   for(int i = 1; i <= MaxCandlesBollLookback; i++)
   {
      double low = iLow(symbol, PERIOD_CURRENT, i);
      double bollLower = iBollingerGet(handle, i);
      if(low <= bollLower)
         return true;
   }
   return false;
}

int Get_handles_stockAD(string symbol)
{
   if(StringLen(symbol) == 0)
      return INVALID_HANDLE;

   int handle = iCustom(symbol, PERIOD_CURRENT, "stochastic_AD", InpStochPeriod, InpStochDPeriod, VOLUME_TICK);
   if(handle == INVALID_HANDLE)
      PrintFormat("Failed to create stochastic_AD handle for %s: %d", symbol, GetLastError());

   return handle;
}

int Get_handles_Bollinger(string symbol)
{
   if(StringLen(symbol) == 0)
      return INVALID_HANDLE;

   int handle = iBands(symbol, PERIOD_CURRENT, BollPeriod, BollShift, BollDev, BollApPrice);
   if(handle == INVALID_HANDLE)
      PrintFormat("Failed to create Bollinger handle for %s: %d", symbol, GetLastError());

   return handle;
}

double iStochADGet(const int handle, const int index)
{
   double buffer[1];
   ResetLastError();
   if(CopyBuffer(handle, 0, index, 1, buffer) <= 0)
   {
      PrintFormat("Failed to copy stochastic_AD data, error=%d", GetLastError());
      return 0.0;
   }
   return buffer[0];
}

double iAMAGet(const int handle, const int index)
{
   double buffer[1];
   ResetLastError();
   if(CopyBuffer(handle, 0, index, 1, buffer) <= 0)
   {
      PrintFormat("Failed to copy AMA data, error=%d", GetLastError());
      return 0.0;
   }
   return buffer[0];
}

double iBollingerGet(const int handle, const int index)
{
   double buffer[1];
   ResetLastError();
   if(CopyBuffer(handle, LOWER_BAND, index, 1, buffer) <= 0)
   {
      PrintFormat("Failed to copy Bollinger lower band data, error=%d", GetLastError());
      return 0.0;
   }
   return buffer[0];
}

int Get_handles_ATR(string symbol)
{
   if(StringLen(symbol) == 0)
      return INVALID_HANDLE;

   int handle = iATR(symbol, PERIOD_CURRENT, ATR_Period);
   if(handle == INVALID_HANDLE)
      PrintFormat("Failed to create ATR handle for %s: %d", symbol, GetLastError());

   return handle;
}

double iATRGet(const int handle, const int index)
{
   double buffer[1];
   ResetLastError();
   if(CopyBuffer(handle, 0, index, 1, buffer) <= 0)
   {
      PrintFormat("Failed to copy ATR data, error=%d", GetLastError());
      return 0.0;
   }
   return buffer[0];
}