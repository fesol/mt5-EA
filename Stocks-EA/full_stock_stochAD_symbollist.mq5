#include <Trade\Trade.mqh>
   CPositionInfo  posinfo;                   // trade position object
   CTrade         trade;                     // trading object
   COrderInfo     ordinfo;                   // pending orders object
   

enum LotTyp     {Lot_per_1k_Capital=0, Fixed_Lot_Size=1};



double ustec10ma,ustec20ma;
double current_balance, current_equity, current_profit_pcnt;


input int  stoploss_candles_low = 3;
input double TPfactor = 1; // tp factor

input bool allowsells = false; // allow sells



input double profit_pcnt_closeall = 6; // when total profit reaches this percentage of the account balance, close all

input double VolumeMAmultiplier = 1.5;
input int    VolumeMAperiod = 20; 

// AMA 1
input uint                 InpPeriodAMAperiod       =  5;            // AMA period 1 
input uint                 InpPeriodAMAfast         =  3;            // MA period 1 fast
input uint                 InpPeriodAMAslow         =  8;            // MA period 1 slow

// AMA 2
input uint                 InpPeriodAMAperiod_2       =  8;            // MA period 2
input uint                 InpPeriodAMAfast_2         =  5;            // MA period 2 fast
input uint                 InpPeriodAMAslow_2         =  21;            // MA period 2 slow

input ENUM_TIMEFRAMES      InptUSTECtrendfilderTimeframe = PERIOD_D1 ;

input int                 InpNumberCandlesEMAabove = 20;            // Minimum number of candles AMA is above to consider trend

// Stochastic RSI
input int                     InpStochDPeriod               = 3;                                   // D
input int                     InpStochPeriod                = 14;                                  // Stochastic Period
input int                     stoch_level_buy                 = 20;
input int                     stoch_level_sell                = 80;
input int                     Second_crose_MaxCandles            = 13; 

// Bollinger BANDS

input int                  BollPeriod    =     20; 
input int                  BollShift     =      1;
input double               BollDev       =      3;
input ENUM_APPLIED_PRICE   BollApPrice   =   PRICE_MEDIAN;
input int                  MaxCandlesBollLookback = 10;   // Check if any of the previous N candles under Bollinger lower

// ATR

input int            ATR_Period = 14;
input double         ATR_Multiplier = 1;

input group "=== EA specific Variables ==="
   input ulong    InpMagic         = 44444; // EA Unique ID (Magic No)




input double RiskPercent     =         1;
input int    BarsSince            = 3; // No of Bars before new trade can be take
input int    BarsMaxOpen    = 15; //No Bars to close position
input int    MaxTrades    = 1; // Max number of positions per symbol
input int    MinBarsData  = 1; //Minimum number of bars history on the symbol to select it



input bool UseUstecPerformanceFilter = true;
double  nqPriceCurrent,  nqPricePrevious;
input int periodBars = 20; // Bars to calculate percentage increase
input double Performancethreshold = 1; //Min percentage of stock perfomance above NQ index



input group "=== Trade Management ==="
   input LotTyp Lot_Type             = 0; // Type of Lotsize
   input double Lotsize              = 0.02; // Lotsize if Fixed
   input double Lotsizeper1000       = 0.01; // Lotsize per 1000 Capital
   input int    MaxSpread            = 15;  // max spread in 
   input int    Max_positions        = 1; // Max positions allowed per symbol
   
   input ENUM_APPLIED_PRICE AppPrice = PRICE_MEDIAN; 


   string sep  = ",";
   int handle_stockAD[], handle_Bollinger[], handle_iATRs[], handle_AMA1ustec, handle_AMA2ustec;

string TradableSymbols[];
// top 100nasdaq according to deepsek
//string nasdaqSymbols[] = {"AAPL.NAS","MSFT.NAS","GOOG.NAS","GOOGL.NAS","AMZN.NAS","NVDA.NAS","META.NAS","TSLA.NAS","AVGO.NAS","PEP.NAS","COST.NAS","ASML.NAS","AZN.NAS","ADBE.NAS","CSCO.NAS","TMUS.NAS","CMCSA.NAS","TXN.NAS","NFLX.NAS","QCOM.NAS","AMGN.NAS","HON.NAS","INTU.NAS","SBUX.NAS","GILD.NAS","ADI.NAS","ISRG.NAS","AMD.NAS","REGN.NAS","MDLZ.NAS","VRTX.NAS","PYPL.NAS","ADP.NAS","MRNA.NAS","LRCX.NAS","SNPS.NAS","CDNS.NAS","MU.NAS","ATVI.NAS","MELI.NAS","KLAC.NAS","CSX.NAS","PANW.NAS","ORLY.NAS","MNST.NAS","KDP.NAS","KHC.NAS","MAR.NAS","CTAS.NAS","NXPI.NAS","EXC.NAS","FTNT.NAS","WDAY.NAS","CHTR.NAS","MCHP.NAS","ADSK.NAS","ASAN.NAS","ROST.NAS","BIIB.NAS","DXCM.NAS","IDXX.NAS","WBD.NAS","ODFL.NAS","CPRT.NAS","PAYX.NAS","FAST.NAS","GFS.NAS","PCAR.NAS","XEL.NAS","SGEN.NAS","VRSK.NAS","ANSS.NAS","CTSH.NAS","DDOG.NAS","ALGN.NAS","MRVL.NAS","EA.NAS","WBA.NAS","CSGP.NAS","BKR.NAS","ZS.NAS","TEAM.NAS","ILMN.NAS","LULU.NAS","CRWD.NAS","DLTR.NAS","ENPH.NAS","FANG.NAS","TTD.NAS","SWKS.NAS","SPLK.NAS","CDW.NAS","VRSN.NAS","OKTA.NAS","CEG.NAS","ZM.NAS","MDB.NAS","TTWO.NAS","EBAY.NAS","DASH.NAS","VRTX.NAS","JD.NAS","PDD.NAS","NXST.NAS","GLPI.NAS","MTCH.NAS","FOXA.NAS","FOX.NAS","TRGP.NAS"};
//string nasdaqSymbols[] = {"AMD.NAS","NVDA.NAS","MSFT.NAS","AAPL.NAS","TSLA.NAS","AMZN.NAS","GOOG.NAS","AVGO.NAS","COST.NAS","MDLZ.NAS","VRTX.NAS","PYPL.NAS","PLTR.NAS","CSCO.NAS","MU.NAS","AMAT.NAS","INTU.NAS","LRCX.NAS","QCOM.NAS","TXN.NAS","RGEN.NAS","ADP.NAS","GILD.NAS","SBUX.NAS"};
//string nasdaqSymbols[] = {"HUBB.NYSE"};


// top 100nasdaq according to deepsek
//string nasdaqSymbols[] = {"AAPL.NAS","MSFT.NAS","GOOG.NAS","AMZN.NAS","NVDA.NAS","TSLA.NAS","AVGO.NAS","PLTR.NAS","PEP.NAS","COST.NAS","ASML.NAS","AZN.NAS","ADBE.NAS","CSCO.NAS","TMUS.NAS","CMCSA.NAS","TXN.NAS","NFLX.NAS","QCOM.NAS","AMGN.NAS","HON.NAS","INTU.NAS","SBUX.NAS","GILD.NAS","ADI.NAS","ISRG.NAS","AMD.NAS","REGN.NAS","MDLZ.NAS","VRTX.NAS","PYPL.NAS","ADP.NAS","MRNA.NAS","LRCX.NAS","SNPS.NAS","CDNS.NAS","MU.NAS","ATVI.NAS","MELI.NAS","KLAC.NAS","CSX.NAS","PANW.NAS","ORLY.NAS","MNST.NAS","KDP.NAS","KHC.NAS","MAR.NAS","CTAS.NAS","NXPI.NAS","EXC.NAS","FTNT.NAS","WDAY.NAS","CHTR.NAS","MCHP.NAS","ADSK.NAS","ASAN.NAS","ROST.NAS","BIIB.NAS","DXCM.NAS","IDXX.NAS","WBD.NAS","ODFL.NAS","CPRT.NAS","PAYX.NAS","FAST.NAS","GFS.NAS","PCAR.NAS","XEL.NAS","SGEN.NAS","VRSK.NAS","ANSS.NAS","CTSH.NAS","DDOG.NAS","ALGN.NAS","MRVL.NAS","EA.NAS","WBA.NAS","CSGP.NAS","BKR.NAS","ZS.NAS","TEAM.NAS","ILMN.NAS","LULU.NAS","CRWD.NAS","DLTR.NAS","ENPH.NAS","FANG.NAS","TTD.NAS","SWKS.NAS","SPLK.NAS","CDW.NAS","VRSN.NAS","OKTA.NAS","CEG.NAS","ZM.NAS","MDB.NAS","TTWO.NAS","EBAY.NAS","DASH.NAS","VRTX.NAS","JD.NAS","PDD.NAS","NXST.NAS","GLPI.NAS","MTCH.NAS","FOXA.NAS","FOX.NAS","TRGP.NAS"};

//string nasdaqSymbols[] = {"F40","BKNG.NAS","MELI.NAS","KLAC.NAS","MPWR.NAS","EQIX.NAS","REGN.NAS","IDXX.NAS","INTU.NAS","MVRS.NAS","QQQ.NAS","ULTA.NAS","AXON.NAS","ISRG.NAS","CASY.NAS","CRWD.NAS","UTHR.NAS","MSFT.NAS","CYBR.NAS","CACC.NAS","TSLA.NAS","VRTX.NAS","MDB.NAS","ALNY.NAS","AVGO.NAS","LPLA.NAS","LITE.NAS","IDCC.NAS","ADBE.NAS","CDNS.NAS","GOOG.NAS","AMGN.NAS","WLTW.NAS","SOXX.NAS","ADSK.NAS","STX.NAS","PODD.NAS","MAR.NAS","ADI.NAS","AAPL.NAS","ERIE.NAS","AMAT.NAS","EXPE.NAS","CME.NAS","ZBRA.NAS"};



// best 200 stocks from NAS AND NYSE BY SCRIPT
//300string nasdaqSymbols[] = {"BKNG.NAS","AZO.NYSE","MPWR.NAS","UI.NYSE","HUBS.NYSE","IDXX.NAS","IT.NYSE","GS.NYSE","EME.NYSE","CW.NYSE","DDS.NYSE","MKL.NYSE","STRL.NAS","ALNY.NAS","LULU.NAS","UNH.NYSE","LITE.NAS","MCK.NYSE","ULTA.NAS","FDS.NYSE","GHC.NYSE","STX.NAS","MELI.NAS","CVNA.NYSE","AVAV.NAS","MOH.NYSE","IDCC.NAS","AVGO.NAS","MTD.NYSE","RH.NYSE","PWR.NYSE","BLK.NYSE","CHE.NYSE","CASY.NAS","HCA.NYSE","MDB.NAS","WSO.NYSE","CYBR.NAS","MU.NAS","CMI.NYSE","DAVE.NAS","SITM.NAS","UTHR.NAS","CRWD.NAS","EQIX.NAS","MLM.NYSE","HII.NYSE","QQQ.NAS","AMD.NAS","CIEN.NYSE","NOC.NYSE","LLY.NYSE","ROK.NYSE","GOOG.NAS","ERIE.NAS","MUSA.NYSE","TYL.NYSE","TEAM.NAS","RL.NYSE","ACN.NYSE","PLTR.NAS","MNDY.NAS","FSLR.NAS","MORN.NAS","ROP.NAS","ORCL.NYSE","IBP.NYSE","NET.NYSE","LII.NYSE","TEL.NYSE","AMG.NYSE","SPOT.NYSE","HOOD.NAS","SOXX.NAS","ZS.NAS","MSTR.NAS","ADBE.NAS","GD.NYSE","FIVE.NAS","BE.NYSE","HEI.NYSE","MTZ.NYSE","SNOW.NYSE","IRTC.NAS","HWM.NYSE","CELC.NAS","WCC.NYSE","EXPE.NAS","AEM.NYSE","THC.NYSE","COIN.NAS","AYI.NYSE","JBL.NYSE","AMAT.NAS","SANM.NAS","COST.NAS","GWW.NYSE","POOL.NAS","CAR.NAS","INTU.NAS","NVDA.NAS","NRG.NYSE","JLL.NYSE","EA.NAS","GDDY.NYSE","VRSK.NAS","JPM.NYSE","CRM.NYSE","TER.NAS","W.NYSE","HUBB.NYSE","BOOT.NYSE","CAH.NYSE","DASH.NAS","ZBRA.NAS","ALGN.NAS","CDNS.NAS","AXON.NAS","KTOS.NAS","GDXJ.NYSE","TSEM.NAS","LDOS.NYSE","BABA.NYSE","ETN.NYSE","LECO.NAS","RTX.NYSE","MKSI.NAS","TDY.NYSE","STZ.NYSE","TTWO.NAS","PODD.NAS","PCTY.NAS","NEM.NYSE","AU.NYSE","WELL.NYSE","NTRA.NAS","CCJ.NYSE","NTES.NAS","ADI.NAS","WYNN.NAS","MPC.NYSE","JNJ.NYSE","CLX.NYSE","MKTX.NAS","TPR.NYSE","SAM.NYSE","ANET.NYSE","VEEV.NYSE","VST.NYSE","VMC.NYSE","MS.NYSE","ORA.NYSE","NXST.NAS","ALLE.NYSE","SIMO.NAS","VRTX.NAS","ATI.NYSE","SCCO.NYSE","TFX.NYSE","BA.NYSE","NICE.NAS","GLW.NYSE","SIL.NYSE","GDX.NYSE","ABBV.NYSE","DLTR.NAS","DELL.NYSE","EPAM.NYSE","RY.NYSE","RACE.NYSE","ENS.NYSE","EWY.NYSE","DG.NYSE","AN.NYSE","BDX.NYSE","ODFL.NAS","GKOS.NYSE","BIDU.NAS","UHS.NYSE","ALB.NYSE","JCI.NYSE","AER.NYSE","AVB.NYSE","XLK.NYSE","BMI.NYSE","DVA.NYSE","ZTS.NYSE","STE.NYSE","DDOG.NAS","DPZ.NYSE","TRV.NYSE","MSI.NYSE","SE.NYSE","C.NYSE","WMS.NYSE","IUSG.NAS","PAYC.NYSE","HLT.NYSE","CPA.NYSE","MRCY.NAS","STLD.NAS","R.NYSE","NTRS.NAS","ESS.NYSE","GNRC.NYSE","GWRE.NYSE","TGT.NYSE","LH.NYSE","CDW.NAS","IQV.NYSE","BK.NYSE","PAYX.NAS","INCY.NAS","MASI.NAS","EL.NYSE","IBB.NAS","TMUS.NAS","EFX.NYSE","IEX.NYSE","CBRE.NYSE","AXSM.NAS","NDSN.NAS","NUE.NYSE","WDAY.NAS","SNX.NYSE","STT.NYSE","EXAS.NAS","GVA.NYSE","JAZZ.NAS","ROKU.NAS","VRSN.NAS","DHI.NYSE","BCO.NYSE","WAT.NYSE","ATO.NYSE","BLDR.NAS","TJX.NYSE","NVS.NYSE","UPS.NYSE","ONTO.NYSE","CI.NYSE","AMGN.NAS","KEYS.NYSE","MAA.NYSE","ALX.NYSE","TRGP.NYSE","ROST.NAS","STN.NYSE","EG.NYSE","CME.NAS","XYL.NYSE","RVMD.NAS","EBAY.NAS","CRUS.NAS","VONG.NAS","EXPD.NYSE","HSY.NYSE","PTC.NAS","IAU.NYSE","BIIB.NAS","ACWI.NAS","CINF.NAS","NBIX.NAS","ADSK.NAS","TOL.NYSE","MSGS.NYSE","SNEX.NAS","ECL.NYSE","AAXJ.NAS","GILD.NAS","MMM.NYSE","CRL.NYSE","MCO.NYSE","PSA.NYSE","THG.NYSE","PG.NYSE","DGX.NYSE","INGR.NYSE","J.NYSE","CHKP.NAS","DCI.NYSE","AMZN.NAS","CWST.NAS","EHC.NYSE","TM.NYSE","MAR.NAS","RNR.NYSE","ACM.NYSE","SCHW.NYSE","RVTY.NYSE","L.NYSE","IDA.NYSE","SKYY.NAS","SBAC.NAS","OLLI.NAS","GL.NYSE","EAT.NYSE","PANW.NYSE","BURL.NYSE","PSX.NYSE"};


string nasdaqSymbols[] = {
"AZO.NYSE","BKNG.NAS","MKL.NYSE","MPWR.NAS","IT.NYSE","MELI.NAS","HUBS.NYSE","IDXX.NAS",
"GS.NYSE","UNH.NYSE","MCK.NYSE","CW.NYSE","ALNY.NAS","EME.NYSE","GHC.NYSE","RH.NYSE",
"STRL.NAS","SPOT.NYSE","LULU.NAS","FDS.NYSE","ULTA.NAS","AVGO.NAS","IDCC.NAS","LITE.NAS",
"CYBR.NAS","STX.NAS","CRWD.NAS","MOH.NYSE","CASY.NAS","EQIX.NAS","WSO.NYSE","CHE.NYSE",
"GWW.NYSE","ADBE.NAS","AVAV.NAS","MUSA.NYSE","PWR.NYSE","HCA.NYSE","ERIE.NAS","RL.NYSE",
"MU.NAS","ACN.NYSE","MORN.NAS","NET.NYSE","TYL.NYSE","BLK.NYSE","HII.NYSE","QQQ.NAS",
"LII.NYSE","CMI.NYSE","CIEN.NYSE","SITM.NAS","AXON.NAS","ROK.NYSE","MTD.NYSE","NOC.NYSE",
"ZBRA.NAS","MNDY.NAS","ZS.NAS","GOOG.NAS","TEAM.NAS","SNOW.NYSE","HWM.NYSE","AMD.NAS",
"POOL.NAS","LLY.NYSE","JBL.NYSE","TEL.NYSE","SAM.NYSE","ORCL.NYSE","STZ.NYSE","AEM.NYSE",
"UTHR.NAS","CRM.NYSE","MDB.NAS","MTZ.NYSE","NRG.NYSE","MLM.NYSE","AMG.NYSE","HEI.NYSE",
"ALGN.NAS","FIVE.NAS","SOXX.NAS","MKTX.NAS","TFX.NYSE","JPM.NYSE","CAR.NAS","SANM.NAS",
"TTWO.NAS","EXPE.NAS","GD.NYSE","CAH.NYSE","VRSN.NAS","FSLR.NAS","IBP.NYSE","TDY.NYSE",
"THC.NYSE","BABA.NYSE","PODD.NAS","INTU.NAS","MSTR.NAS","GDDY.NYSE","NTES.NAS","ODFL.NAS",
"KTOS.NAS","WCC.NYSE","NVDA.NAS","BA.NYSE","EPAM.NYSE","AMAT.NAS","MSI.NYSE","TPR.NYSE",
"W.NYSE","GDXJ.NYSE","CLX.NYSE","RTX.NYSE","VEEV.NYSE","WELL.NYSE","CDNS.NAS","BOOT.NYSE",
"AU.NYSE","BLDR.NAS","JLL.NYSE","VST.NYSE","SE.NYSE","EA.NAS","VRSK.NAS","ONTO.NYSE",
"NICE.NAS","GKOS.NYSE","NTRA.NAS","IEX.NYSE","AYI.NYSE","TGT.NYSE","NEM.NYSE","BDX.NYSE",
"ANF.NYSE","TER.NAS","PCTY.NAS","VRTX.NAS","TSEM.NAS","DLTR.NAS","DE.NYSE","WST.NYSE",
"AN.NYSE","LECO.NAS","AVB.NYSE","JNJ.NYSE","MPC.NYSE","ZTS.NYSE","ATI.NYSE","ABBV.NYSE",
"AMR.NYSE","MS.NYSE","CCJ.NYSE","PSA.NYSE","GDX.NYSE","CME.NAS","DG.NYSE","SIMO.NAS",
"UPS.NYSE","GWRE.NYSE","ANET.NYSE","WYNN.NAS","ADI.NAS","SIL.NYSE","GLW.NYSE","CDW.NAS",
"AXSM.NAS","MKSI.NAS","JCI.NYSE","NXST.NAS","ESS.NYSE","AER.NYSE","LH.NYSE","LAD.NYSE",
"STE.NYSE","DVA.NYSE","ALLE.NYSE","C.NYSE","MRCY.NAS","ORA.NYSE","EFX.NYSE","MSCI.NYSE",
"COST.NAS","BIDU.NAS","BK.NYSE","AAPL.NAS","MSFT.NAS","AMZN.NAS","META.NAS","NOW.NYSE","PANW.NAS","LRCX.NAS",
"KLAC.NAS","TSM.NAS"
};


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){

   trade.SetExpertMagicNumber(InpMagic);
   
   TesterHideIndicators(true);

   handle_AMA1ustec = iAMA("USTEC", InptUSTECtrendfilderTimeframe, InpPeriodAMAperiod, 
                     InpPeriodAMAfast, InpPeriodAMAslow, 0, PRICE_CLOSE);
    
   handle_AMA2ustec = iAMA("USTEC", InptUSTECtrendfilderTimeframe, InpPeriodAMAperiod_2, 
                     InpPeriodAMAfast_2, InpPeriodAMAslow_2, 0, PRICE_CLOSE);
                     
    if (handle_AMA1ustec == INVALID_HANDLE || handle_AMA2ustec == INVALID_HANDLE) {
         Print ("ERROR: failed to get USTEC AMA handlers!!!!!"); 
         return INIT_FAILED;
    }
   
   ArrayPrint(nasdaqSymbols);
   
   int j = ArraySize(nasdaqSymbols);
   ArrayResize(TradableSymbols,j);
   ArrayCopy(TradableSymbols,nasdaqSymbols);
   
   // REMOVE THIS LINE - Filtering happens AFTER we check indicator handles
   // FilterTradableSymbols(TradableSymbols,PERIOD_CURRENT,100);
   
   // First, check if we can create indicators for each symbol
   string filteredSymbols[];
   int filteredCount = 0;
   
   for(int i = 0; i < j; i++)
   {
      string symbolName = nasdaqSymbols[i];
      
      // Check if symbol is tradable
      ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbolName, SYMBOL_TRADE_MODE);
      if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
      {
         PrintFormat("Symbol %s is not tradable", symbolName);
         continue;
      }
      
      // Make sure symbol is in Market Watch
      if(!SymbolInfoInteger(symbolName, SYMBOL_VISIBLE))
      {
         if(!SymbolSelect(symbolName, true))
         {
            PrintFormat("Failed to add %s to Market Watch", symbolName);
            continue;
         }
      }
      
      // Try to create all 3 indicators
      int testHandleBB = iBands(symbolName, PERIOD_CURRENT, BollPeriod, BollShift, BollDev, BollApPrice);
      int testHandleStochAD = iCustom(symbolName, PERIOD_CURRENT, "stochastic_AD", InpStochPeriod, InpStochDPeriod, VOLUME_TICK);
      int testHandleATR = iATR(symbolName, PERIOD_CURRENT, ATR_Period);
      
      bool allIndicatorsOK = true;
      
      if(testHandleBB == INVALID_HANDLE)
      {
         PrintFormat("Failed to create Bollinger Bands for %s", symbolName);
         allIndicatorsOK = false;
      }
      
      if(testHandleStochAD == INVALID_HANDLE)
      {
         PrintFormat("Failed to create Stochastic AD for %s", symbolName);
         allIndicatorsOK = false;
      }
      
      if(testHandleATR == INVALID_HANDLE)
      {
         PrintFormat("Failed to create ATR for %s", symbolName);
         allIndicatorsOK = false;
      }
      
      // Release test handles
      if(testHandleBB != INVALID_HANDLE) IndicatorRelease(testHandleBB);
      if(testHandleStochAD != INVALID_HANDLE) IndicatorRelease(testHandleStochAD);
      if(testHandleATR != INVALID_HANDLE) IndicatorRelease(testHandleATR);
      
      if(!allIndicatorsOK)
      {
         PrintFormat("Skipping symbol %s - indicator creation failed", symbolName);
         continue;
      }
      
      // Check for minimum bars
      if(Bars(symbolName, PERIOD_CURRENT) < 100)
      {
         PrintFormat("Symbol %s has insufficient data: %d bars", symbolName, Bars(symbolName, PERIOD_CURRENT));
         continue;
      }
      
      // Symbol passed all checks - add to filtered array
      ArrayResize(filteredSymbols, filteredCount + 1);
      filteredSymbols[filteredCount] = symbolName;
      filteredCount++;
      PrintFormat("✓ Symbol %s added to watchlist", symbolName);
   }
   
   // Update TradableSymbols with filtered results
   ArrayResize(TradableSymbols, filteredCount);
   ArrayCopy(TradableSymbols, filteredSymbols, 0, 0, WHOLE_ARRAY);
   
   Print ("SIZE NASDAQSYMBOLS ========== ", j);
   Print ("SIZE TradableSymbols ========== ", filteredCount);
   
   // Now create the actual indicator handles for filtered symbols
   ArraySetAsSeries(handle_stockAD,true);
   ArraySetAsSeries(handle_Bollinger,true);
   ArraySetAsSeries(handle_iATRs,true);
   
   ArrayResize(handle_stockAD, filteredCount);
   ArrayResize(handle_Bollinger, filteredCount);
   ArrayResize(handle_iATRs, filteredCount);
   
   ArrayInitialize(handle_stockAD, INVALID_HANDLE);
   ArrayInitialize(handle_Bollinger, INVALID_HANDLE);
   ArrayInitialize(handle_iATRs, INVALID_HANDLE);

   for (int i = filteredCount - 1; i >= 0; i--){
         handle_stockAD[i] = Get_handles_stockAD(TradableSymbols[i]);
         handle_Bollinger[i] = Get_handles_Bollinger(TradableSymbols[i]);
         handle_iATRs[i] = Get_handles_ATR(TradableSymbols[i]);
         
         // If any handle creation fails now, remove the symbol
         if(handle_stockAD[i] == INVALID_HANDLE || handle_Bollinger[i] == INVALID_HANDLE || handle_iATRs[i] == INVALID_HANDLE)
         {
            PrintFormat("Warning: Failed to create handles for %s - removing from watchlist", TradableSymbols[i]);
            // Remove this symbol from the array
            for(int k = i; k < filteredCount - 1; k++)
            {
               TradableSymbols[k] = TradableSymbols[k + 1];
               handle_stockAD[k] = handle_stockAD[k + 1];
               handle_Bollinger[k] = handle_Bollinger[k + 1];
               handle_iATRs[k] = handle_iATRs[k + 1];
            }
            filteredCount--;
         }
   }
   
   // Resize arrays to final count
   ArrayResize(TradableSymbols, filteredCount);
   ArrayResize(handle_stockAD, filteredCount);
   ArrayResize(handle_Bollinger, filteredCount);
   ArrayResize(handle_iATRs, filteredCount);
   
   Print ("Array size: ", filteredCount, " symbols loaded successfully");
   
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release all valid indicator handles
   for(int i = 0; i < ArraySize(handle_stockAD); i++)
   {
      if(handle_stockAD[i] != INVALID_HANDLE)
         IndicatorRelease(handle_stockAD[i]);
      if(handle_Bollinger[i] != INVALID_HANDLE)
         IndicatorRelease(handle_Bollinger[i]);
      if(handle_iATRs[i] != INVALID_HANDLE)
         IndicatorRelease(handle_iATRs[i]);
   }
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
  
   
    current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
    current_profit_pcnt=((current_equity - current_balance) / current_balance) * 100;
    
   if( current_profit_pcnt > profit_pcnt_closeall ) {
         Print("Closing all positions since profit is above :) ", profit_pcnt_closeall); 
         ClosePositions();
   }
   
   //Print ("SYMBOL INFO SECTOR ============= ", SymbolInfoString(Symbol(),SYMBOL_SECTOR_NAME));



   
   if (!IsNewBar()) return;
   
    //double ustec10ma = CalculateAMASimple(InpPeriodAMAperiod,InpPeriodAMAfast,InpPeriodAMAslow,"USTEC",1);
    //double ustec20ma = CalculateAMASimple(InpPeriodAMAperiod_2,InpPeriodAMAfast_2,InpPeriodAMAslow_2,"USTEC",2);
    
   
   ustec10ma=iAMAGet(handle_AMA1ustec,0);
   ustec20ma=iAMAGet(handle_AMA2ustec,0);
   
   //double usteclose=iClose("USTEC",PERIOD_D1,1);
   //if (usteclose<ustec20ma) { return;}
   
   //if (ustec10ma<ustec20ma) { Print ("USTEC is bearish, not opening new positions "); return;}
   //if (ustec10ma<ustec20ma) { ClosePositions(); return;}
   
   
   for(int i=ArraySize(TradableSymbols)-1; i>=0; i--){
      //Print ("TOTAL STOCKS ============ ", ArraySize(nasdaqSymbols));
      RunSymbols(TradableSymbols[i], i);
   }
}

void RunSymbols (string symbol, int count) {
   
   if (symbol == NULL ) return;

      
      // Check if symbol exists and has data
      if(!SymbolSelect(symbol, true)) {
         Print("⚠ Symbol not available: ", symbol);
         return;
      }
      
      if(Bars(symbol, PERIOD_CURRENT) < 100) {
         Print("⚠ Insufficient data for: ", symbol, " (", Bars(symbol, PERIOD_CURRENT), " bars)");
         return;
      }
     
   // Only proceed if handles are valid
   if(handle_stockAD[count] == INVALID_HANDLE || handle_Bollinger[count] == INVALID_HANDLE ) {
      return;
   }

   
    if (UseUstecPerformanceFilter) {  //Filters Stocks with perfomance abouve USTEC performance
   
             // Get stock price data
          double stockPriceCurrent = iClose(symbol, PERIOD_CURRENT, 0);
          double stockPricePrevious = iClose(symbol, PERIOD_CURRENT, periodBars);
      
        
          // Get NQ index price data
          nqPriceCurrent = iClose("USTEC", PERIOD_CURRENT, 1);
          nqPricePrevious = iClose("USTEC", PERIOD_CURRENT, periodBars);
      
          // Calculate percentage change for stock and NQ
          double stockPercentChange = (stockPriceCurrent - stockPricePrevious) / stockPricePrevious * 100;
          double nqPercentChange = (nqPriceCurrent - nqPricePrevious) / nqPricePrevious * 100;
          
          // Calculate performance difference
          double relativePerformance = stockPercentChange - nqPercentChange;
          
          if ( relativePerformance < Performancethreshold ) return;
    }
    
    double StochAD_1=iStochADGet(handle_stockAD[count], 1);
    double StochAD_2=iStochADGet(handle_stockAD[count], 2);
   
    double Bollinger_1 = iBollingerGet(handle_Bollinger[count],1);
    //double slowAMA = iAMAGet(handle_AMA2[count],1);  
    
    Print("Stoch AD 1 ---  ", StochAD_1);
    Print("Stoch AD 2 ---  ", StochAD_2);
    
    Print("BOLLINGER LOWER ---  ", Bollinger_1);
    //Print("slowAMA ---  ", slowAMA);
    

      
   if( (StochAD_1>stoch_level_buy) && (StochAD_2<stoch_level_buy)  && recentCandleBelowBollinger(handle_Bollinger[count],symbol) ){// {
 
         int BuyTotal = 0;
         
         for(int i=PositionsTotal()-1; i>=0; i--){
            posinfo.SelectByIndex(i);
            if (posinfo.PositionType()==POSITION_TYPE_BUY && posinfo.Symbol()==symbol && posinfo.Magic()==InpMagic) BuyTotal++;
         }
         
         if (BuyTotal > (Max_positions-1) ){return;} // Exit the function
               
               double Ask = NormalizeDouble(SymbolInfoDouble(symbol,SYMBOL_ASK),_Digits); // Get and normalize the current Ask price
         
               int low_index=iLowest(symbol,PERIOD_CURRENT,MODE_LOW,stoploss_candles_low,1);
               double sl=iLow(symbol,PERIOD_CURRENT,low_index);
               double tp=Ask+TPfactor*(Ask-sl);
               double ATR = iATRGet(handle_iATRs[count],0);
               if( (Ask-sl) < ATR) sl = sl - (ATR*ATR_Multiplier);
         

         double vol=CalculateLotSize(Ask,sl);

         
         trade.Buy(vol,symbol,Ask,sl,tp);
         return; // Exit the function
      }
      



}
//+------------------------------------------------------------------+

bool IsNewBar (){
   static datetime previousTime=0;
   datetime CurrentTime = iTime (_Symbol, PERIOD_CURRENT,0);
   if (previousTime!=CurrentTime){
      previousTime=CurrentTime;
      return true;
   }
   return false;
}




string PricevsMovAvg(double MAfast, double MAslow){
   if(MAfast>MAslow) return "above";
   if(MAfast<MAslow) return "below";
 
 return "ERROR in PRICE vs Moving average!!!";
}





//+------------------------------------------------------------------+
//| caculate lot sisze                       |
//+------------------------------------------------------------------+
double CalculateLotSize(double price, double sl)
{
    if (RiskPercent < 0 || RiskPercent  > 100) {
        Print("Error: Invalid risk percentage");
        return -1;
    }
    
    
    double SLDistance= MathAbs(price-sl);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);    // Free margin on the account in the deposit currency
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE); // Minimal price change of ticks
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);  // Value per tick in the deposit currency
    double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);    // Minimum lot step
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);         // Minimum allowed lot size
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);         // Maximum allowed lot size
    
    
    double riskVolumeStep = (SLDistance / tickSize) * tickValue * volumeStep;

    double risk = (RiskPercent * freeMargin) / 100;

    // calculate lot size by dividing risk by risk per volume step
    double lots = MathFloor(risk / riskVolumeStep) * volumeStep;
    
    if (lots < minLot) lots = minLot;
    if (lots > maxLot) lots = maxLot;

    return lots;
}



void ClosePositions(){

   //Print("Closing all positions !!!");
   for(int i = PositionsTotal() - 1; i >= 0; i--) // loop all Orders
      if(posinfo.SelectByIndex(i) && posinfo.Magic()==InpMagic)  // select an order
        {
         trade.PositionClose(posinfo.Ticket()); // then delete it --period
         Print("Target profit reached!!! :)  Closing all positions");
         Sleep(100); // Relax for 100 ms
        }
}


// Function to find active NYSE stock CFDs and add them to Market Watch if tradable
void FindNYSEStockCFDs(string &symbolsArray[])
{
    ArrayResize(symbolsArray, 0); // Reset output array
    const string NYSESuffix = ".NYSE"; // Suffix to look for
    
    int totalSymbols = SymbolsTotal(false); // Get all broker symbols
    
    for(int i = 0; i < totalSymbols; i++)
    {
        string symbolName = SymbolName(i, false);
        int nameLength = StringLen(symbolName);
        
        // Skip symbols that are too short for the suffix
        if(nameLength <= StringLen(NYSESuffix)) continue;
        

        // Check for NYSE CFD suffix
        if(StringSubstr(symbolName, nameLength - StringLen(NYSESuffix)) == NYSESuffix)
        {
            // Get symbol properties
            bool isSelected = SymbolInfoInteger(symbolName, SYMBOL_SELECT);
            ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbolName, SYMBOL_TRADE_MODE);
            bool isTradable = (tradeMode != SYMBOL_TRADE_MODE_DISABLED);
            //int AvailableBars = Bars(symbolName, PERIOD_CURRENT);
            //bool enoughdata = ( AvailableBars > MinBarsData);
            
            // Market Watch management
            if(isTradable )
            {
                // Add to Market Watch if not present
                if(!isSelected)
                {
                    SymbolSelect(symbolName, true);
                    Sleep(50); // Allow brief time for symbol activation
                }
                
                // Add to results array
                int arraySize = ArraySize(symbolsArray);
                ArrayResize(symbolsArray, arraySize + 1);
                symbolsArray[arraySize] = symbolName;
            }
            else
            {
                // Remove from Market Watch if present
                if(isSelected)
                {
                    SymbolSelect(symbolName, false);
                    Sleep(50); // Allow brief time for removal
                }
            }
        }
    }
    
    // Cleanup: Remove any .NAS symbols that might have been missed
    int marketWatchSymbols = SymbolsTotal(true);
    for(int i = marketWatchSymbols-1; i >= 0; i--)
    {
        string symbolName = SymbolName(i, true);
        if(StringFind(symbolName, NYSESuffix) == StringLen(symbolName) - StringLen(NYSESuffix))
        {
            if(SymbolInfoInteger(symbolName, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
            {
                SymbolSelect(symbolName, false);
            }
        }
    }
}




bool IsVolumeAboveMA(string _symbol)
{
    // Get current volume
    long currentVolume = iTickVolume(_symbol,PERIOD_CURRENT,1);
    
    // Calculate volume SMA
    double volumeMA = CalculateVolumeSMA(VolumeMAperiod, 1, _symbol);
    
    // Check if volume SMA calculation was successful and current volume is above threshold
    if(volumeMA > 0 && currentVolume > (volumeMA * VolumeMAmultiplier))
    {
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Simple Volume SMA calculation (helper function)                 |
//+------------------------------------------------------------------+
double CalculateVolumeSMA(int period, int shift, string _symbol)
{
    if(period <= 0) return 0;
    
    double sum = 0;
    int count = 0;
    
    // Sum volumes for the specified period
    for(int i = shift; i < shift + period; i++)
    {
        sum += (double)iTickVolume(_symbol,PERIOD_CURRENT,i);
        count++;
    }
    
    if(count == 0) return 0;
    return sum / count;
}


double GetEMA(string _symbol, int emaPeriod)
{
   double emaBuffer[];
   if(CopyBuffer(iMA(_symbol, PERIOD_CURRENT, emaPeriod, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 1, emaBuffer) <= 0)
   {
      Print("❌ Failed to get EMA data for ", _symbol, " error: ", GetLastError());
      return 0.0;
   }
   return emaBuffer[0];
}



bool IsAMAtrending(int handlefast, int handleslow)
{
    for(int i = 0; i<=InpNumberCandlesEMAabove; i++)
    {
    
    double fastAMA = iAMAGet(handlefast,1);
    double slowAMA = iAMAGet(handleslow,1);
        // If at any point fast EMA is not above slow EMA, return false
        if(fastAMA < slowAMA)
            return false;
    }
    
    // If we made it through all candles, fast EMA was above slow EMA for entire period
    return true;
}

/*
bool RecentRSICross(int handle, int n)
{
   if(n <= 0) return false;

   for(int i = 2; i <= (n+1); i++)  // check completed bars only
   {
      double prev = iRSIGet(handle, i+1);
      double curr = iRSIGet(handle, i );

      if(prev < 20.0 && curr >= 20.0)
         return true;
   }

   return false;
}
*/
bool recentCandleBelowBollinger(int handle, string _symbol){

   if (_symbol==NULL) {
   //Print ("SKIPING THE STOCHASTIC AD INDICATOR HANDLE CREATEION FOR THE SYMBOL ===== ", _symbol);
   return false;
   }
   
   for (int i = 1; i<=MaxCandlesBollLookback; i++){
         double low=iLow(_symbol,PERIOD_CURRENT,i);
         double bollingerlower=iBollingerGet(handle, i);
         
         if (low<=bollingerlower) return true;
   }

return false;

}

int Get_handles_stockAD(string _symbol) {


   if (_symbol==NULL) {
   Print ("SKIPING THE STOCHASTIC AD INDICATOR HANDLE CREATEION FOR THE SYMBOL ===== ", _symbol);
   return INVALID_HANDLE;
   }
   int handle_stocAD=iCustom(_symbol,PERIOD_CURRENT,"stochastic_AD",InpStochPeriod,InpStochDPeriod,VOLUME_TICK);
 
 //--- if the handle is not created 
   if(handle_stocAD==INVALID_HANDLE)
     {
      //--- tell about the failure and output the error code 
      PrintFormat("Failed to create handle of the iStockAD indicator for the symbol %s/%s, error code %d",
                  _symbol,
                  EnumToString(Period()),
                  GetLastError());
      return INVALID_HANDLE;
      }
 return handle_stocAD;
}



int Get_handles_Bollinger(string _symbol) {


   if (_symbol==NULL) {
   Print ("SKIPING THE iBollinger INDICATOR HANDLE CREATEION FOR THE SYMBOL ===== ", _symbol);
   return INVALID_HANDLE;
   }
   
   int handle_iBoll=iBands(_symbol,PERIOD_CURRENT,BollPeriod,BollShift,BollDev,BollApPrice);
 
 
 //--- if the handle is not created 
   if(handle_iBoll==INVALID_HANDLE)
     {
      //--- tell about the failure and output the error code 
      PrintFormat("Failed to create handle of the iAMA indicator for the symbol %s/%s, error code %d",
                  _symbol,
                  EnumToString(Period()),
                  GetLastError());
      return INVALID_HANDLE;
      }
 return handle_iBoll;
}

//+------------------------------------------------------------------+
//| Get value of buffers for the iRSI                                |
//+------------------------------------------------------------------+
double iStochADGet(const int handle, const int index)
  {
   double StochAD[1];
//--- reset error code
   ResetLastError();
//--- fill a part of the iRSI array with values from the indicator buffer that has 0 index
   if(CopyBuffer(handle,0,index,1,StochAD)<0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the iRSI indicator, error code %d",GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return(0.0);
     }
   return(StochAD[0]);
  }


//+------------------------------------------------------------------+
//| Get value of buffers for the iAMA                                |
//+------------------------------------------------------------------+
double iAMAGet(const int handle, const int index)
  {
   double AMA[1];
//--- reset error code
   ResetLastError();
//--- fill a part of the iAMA array with values from the indicator buffer that has 0 index
   if(CopyBuffer(handle,0,index,1,AMA)<0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the iAMA indicator, error code %d",GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return(0.0);
     }
   return(AMA[0]);
  }


//+------------------------------------------------------------------+
//| Get value of buffers for the bOLLINGER                            |
//+------------------------------------------------------------------+
double iBollingerGet(const int handle, const int index)
  {
   double Boll[1];
//--- reset error code
   ResetLastError();
//--- fill a part of the iBoll array with values from the indicator buffer that has 1 index (LOWER BAND)
   if(CopyBuffer(handle,LOWER_BAND,index,1,Boll)<0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the Boll indicator, error code %d",GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return(0.0);
     }
   return(Boll[0]);
  }

int Get_handles_ATR(string symbol){

   if (symbol==NULL) {
   Print ("SKIPING THE ATR INDICATOR HANDLE CREATEION FOR THE SYMBOL ===== ", symbol);
   return -1;
   }

   int handle_iATR=iATR(symbol,PERIOD_CURRENT,ATR_Period);
//--- if the handle is not created 
   if(handle_iATR==INVALID_HANDLE)
     {
      //--- tell about the failure and output the error code 
      PrintFormat("Failed to create handle of the ATR indicator for the symbol %s/%s, error code %d",
                  symbol,
                  EnumToString(Period()),
                  GetLastError());
           return -1;
     }
 return handle_iATR;
} 


//+------------------------------------------------------------------+
//| Get value of buffers for the iATR                                |
//+------------------------------------------------------------------+
double iATRGet(const int handle_iATR, const int index)
  {
   double ATR[1];
//--- reset error code
   ResetLastError();
//--- fill a part of the iATR array with values from the indicator buffer that has 0 index
   if(CopyBuffer(handle_iATR,0,index,1,ATR)<0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the iATR indicator, error code %d",GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return(0.0);
     }
   return(ATR[0]);
  }
  
//+------------------------------------------------------------------+
//| Filter symbols by tradability and available candles             |
//+------------------------------------------------------------------+
bool FilterTradableSymbols(string &symbols[], ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT, int minBars = 100)
{
    if(ArraySize(symbols) == 0) return false;
    if(minBars <= 0) return false;
    
    string filteredSymbols[];
    int count = 0;
    
    if(timeframe == PERIOD_CURRENT) timeframe = _Period;
    
    for(int i = 0; i < ArraySize(symbols); i++)
    {
        string symbolName = symbols[i];
        
        // Basic checks
        ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbolName, SYMBOL_TRADE_MODE);
        if(tradeMode == SYMBOL_TRADE_MODE_DISABLED) continue;
        
        if(!SymbolInfoInteger(symbolName, SYMBOL_VISIBLE))
            if(!SymbolSelect(symbolName, true)) continue;
        
        // Check candles
        int requiredBars = MathMax(minBars, MathMax(BollPeriod, ATR_Period)) + 10;
        MqlRates rates[];
        if(CopyRates(symbolName, timeframe, 0, requiredBars, rates) < requiredBars) continue;
        
        // Check prices
        double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
        if(bid <= 0 || ask <= 0) continue;
        
        // Indicator creation checks
        int handle_iBoll = iBands(symbolName, timeframe, BollPeriod, BollShift, BollDev, BollApPrice);
        int handle_stocAD = iCustom(symbolName, timeframe, "stochastic_AD", InpStochPeriod, InpStochDPeriod, VOLUME_TICK);
        int handle_iATR = iATR(symbolName, timeframe, ATR_Period);
        
        bool indicatorsOK = (handle_iBoll != INVALID_HANDLE && 
                            handle_stocAD != INVALID_HANDLE && 
                            handle_iATR != INVALID_HANDLE);
        
        // Release handles
        if(handle_iBoll != INVALID_HANDLE) IndicatorRelease(handle_iBoll);
        if(handle_stocAD != INVALID_HANDLE) IndicatorRelease(handle_stocAD);
        if(handle_iATR != INVALID_HANDLE) IndicatorRelease(handle_iATR);
        
        if(!indicatorsOK) continue;
        
        // Add to filtered array
        ArrayResize(filteredSymbols, count + 1);
        filteredSymbols[count] = symbolName;
        count++;
    }
    
    if(count > 0)
    {
        ArrayResize(symbols, count);
        ArrayCopy(symbols, filteredSymbols, 0, 0, WHOLE_ARRAY);
        return true;
    }
    
    ArrayResize(symbols, 0);
    return false;
}