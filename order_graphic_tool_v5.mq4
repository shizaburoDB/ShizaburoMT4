//+------------------------------------------------------------------+
//| 7:26 AM 7/10/2016                              Order_Manager.mq4 |
//|                            Copyright 2016-17, WHRoeder@yahoo.com |
//+------------------------------------------------------------------+
//#property copyright "Copyright © 2016-17, WHRoeder@yahoo.com"
//#property link      "mailto:WHRoeder@yahoo.com"
//#property version   "1.05"

#property copyright "Copyright © 2023, Denta Arvihaknata"
#property link "https://forex-station.com/download/file.php?id=3359829&sid=b6bfcf8153e9e74abd43c04d9dafb897"
#property version "5.0"
#property description "EA - Order Graphic Tool by Denta Arvihaknata"


/* V5 Changes
 * One Cancels Other (OCO.) Two opposite pending orders, when first filled,
 *    other is deleted, (if enabled.)
 * Generalization of PIP for metals and exotics.
 * Trades are shown like the tester does, or when closed orders are dragged onto
 *    the chart (if enabled.)
 *
 * v4 Changes
 * Build 970 broke code. MQL4: Fixed generating events related to mouse movement
 *    and mouse button pressing over objects of OBJ_LABEL and OBJ_TEXT types.
 * Previously, the events were generated incorrectly if they were within other
 *    objects of OBJ_RECTANGLE_LABEL and OBJ_RECTANGLE types.
 * The delay between the indicator and the EA means following price was hit
 *    and miss, with a blank alert.
 * So I refactored it in to one EA. Line count went from 1818 to 642
 *
 * v3 Published: 2015.09.10 10:27
 * 'Money Manager Graphic Tool' indicator by 'takycard' for MetaTrader 4 in
 * the MQL5 Code Base — https://www.mql5.com/en/code/13804
*/

#property strict
/* +--------------------------------------------------------------+
   | []           : PIP = 0.00010                                 |
   | Risk         : 1.00% = 53.33 USD / Balance 5333.34 USD       |
   | Ratio        : no TP [1|2|3|4]                               |
   | SL           : [40.1 pips  50.76 USD]                        |
   | TP           : no TP                                         |
   | Lot Size Max : 0.13                                          |
   | --SandBox-/-OpenOrder----------------                        |
   | Risk     [+-]: 1.00% = 52.73 USD / Balance 5272.81 USD       |
   | Lot Size [+-]: 0.14                                          |
   | SL           : [40.1 pips  50.76 USD]                        |
   | TP           : no TP                                         |
   | Off Show TP Line   On  Show SL Line   Yes Follow price       |
   | [__Order Buy 0.14 lot__]                             [Close] |
   | Min Lot:0.01 / Max Lot:1000.0 / Step:0.01 / SL TP limit:0.0  |
   +--------------------------------------------------------------+  */
enum Priority{ Priority_None, Priority_Lines, Priority_Box, Priority_Buttons };

extern string  BuyLine           = "B";         //Key to Create a Buy Line
extern string  SellLine          = "S";         //Key to Create a Sell Line
extern string  CloseGUI          = "C";         //Key to Close GUI
extern double  InitialPercent    = 2.0;         //Percentage Initial Risk
extern color   ColorEntry        = clrLime;     //Color of the entry line
extern color   ColorSL           = clrRed;      //Color of the SL line
extern color   ColorTP           = clrGold;     //Color of the TP line
extern ENUM_LINE_STYLE
               LineStyle         = STYLE_SOLID; //Style of Lines
extern int     LineWidth         = 2;           //Width of the line
extern color   ColorBox          = clrBlack;    //Box background color
extern color   ColorText         = clrWhite;    //Box text color
enum Money{ Balance, Equity };
extern bool    RiskBasis         = Balance;     //Risk basis
extern double  CommissionPerLot  =  0.00;       //Commission charged per lot.
extern bool    CreateSL          = true;        //Create a Stop Loss line
extern bool    CreateTP          = true;       //Create a Take Profit line
extern double  TpRatio           = 2.0;         //Default TP Ratio
extern bool    TransparentBox    = false;       //Transparent dialog box
extern int     MagicNumber       = 951357;      //Magic Number
extern bool    OCOEnabled        = true;        //One cancels other
extern bool    ShowTrades        = true;        //Show Trades
extern bool    AlertClosedTrades = true;       //Alert Closed Trades
// updated first tick
int            digitsLots;
int            digitsPip;
double         lotStep;
double         maximumLot;
double         minimumLot;
double         pips2dbl;
double         stopLevel;
double         tickSize;
double         tickValue;
// updated OnChartEvent or perTick
extern double         defaultSLpips  =  3;      // Default SL in Pips
double         direction      =   0;      // Buy=+1/Sell=-1/GUI not visible=0
double         entryPrice, slPrice, tpPrice;
bool           fixedLotsize;
bool           followingPrice;
double         mousePrice;                // Price under mouse.
int            orderType;                 // OP_BUY
int            orgX           =  15;      // X start
int            orgY           =  15;      // Y start
double         sandboxLotsize;
double         sandboxPercent;
bool           tpRatioFixed;
enum Trade_Operation{
      TO_BUY, TO_SELL, TO_BUYLIMIT, TO_SELLLIMIT, TO_BUYSTOP, TO_SELLSTOP,
      TO_BALANCE,                         ///< (6) May occur in history pool.
      TO_CREDIT};                         ///< (7) May occur in history pool.
   const Trade_Operation   MKT_FIRST   = TO_BUY;     ///< (0) OP_BUY.
   const Trade_Operation   MKT_LAST    = TO_SELL;    ///< (1) OP_SELL.
   const Trade_Operation   PND_FIRST   = TO_BUYLIMIT;///< (2) OP_BUYLIMIT.
   const Trade_Operation   PND_LAST    = TO_SELLSTOP;///< (5) OP_SELLSTOP.
   const int               MKT_COUNT   = 2;          ///< (2) [OP_BUY-OP_SELL]
//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool  firstTick,  firstTimer;
int OnInit(){
   if(CommissionPerLot < 0)   return INIT_PARAMETERS_INCORRECT;
   if(InitialPercent <= 0.1)  return INIT_PARAMETERS_INCORRECT;
   firstTick = true; firstTimer  = true;  OnInit2();
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, 1);  // mousePrice
   if(!EventSetTimer(1) )  Alert(StringFormat("EST:%i", _LastError) );
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
//| Custom indicator timer function                                  |
//+------------------------------------------------------------------+
void OnTimer(void){
   if(ShowTrades){
      for(int iPos = OrdersHistoryTotal(); iPos > 0;){   --iPos;
         if(select_order(iPos, SELECT_BY_POS, MODE_HISTORY) )
            create_trades(AlertClosedTrades && !firstTimer);
      }
   }  // ShowTrades
   firstTimer  = false;
}
void OnInit2(void){
   // Must be connected to account server.
   lotStep     = MarketInfo(_Symbol, MODE_LOTSTEP);
   digitsLots  = digits_in(lotStep);
   maximumLot  = MarketInfo(_Symbol, MODE_MAXLOT);
   minimumLot  = MarketInfo(_Symbol, MODE_MINLOT);
   stopLevel   = MarketInfo(_Symbol, MODE_STOPLEVEL);
   tickSize    = MarketInfo(_Symbol, MODE_TICKSIZE);

   /* Don't try to use any price or server related functions in
    * OnInit as there may be no connection/chart yet:
    *    Terminal starts.
    *    indicators/EAs are loaded.
    *    OnInit is called.
    *    For indicators OnCalculate is called with any existing history.
    *    Human may have to enter password, connection to server begins.
    *    New history is received, OnCalculate called again.
    *    New tick is received, OnCalculate/OnTick is called.
    *    Now TickValue, TimeCurrent and prices are valid.
    */
   tickValue   = MarketInfo(_Symbol, MODE_TICKVALUE);
   //if(tickValue != 0){        // handle metals and exotics like USDMXN/USDZAR
   //   firstTick = false;   double   dVpL  = tickValue / tickSize;
   //                                 pips2dbl = tickSize; digitsPip   = 0;
   //   while(dVpL * pips2dbl < 5){   pips2dbl *= 10;      ++digitsPip;   }
   //}else{
   //   digitsPip   = Digits % 2;
   //   pips2dbl    = digitsPip == 0 ? Point : 10.0 * Point;
   //}
   
   if(tickValue != 0){        // handle metals and exotics like USDMXN/USDZAR
      firstTick = false;   double   dVpL  = tickValue / tickSize;
                                    pips2dbl = tickSize; digitsPip   = 0;
   }
   if (Digits % 2 == 1) {      // DE30=1/JPY=3/EURUSD=5 forum.mql4.com/43064#515262
      //pips2dbl    = Point*10; digitsPip = 1;
      pips2dbl *= 10; digitsPip = 1;
   } else {
      pips2dbl    = Point;  //digitsPip = 0; 
   }

   double   minGapPips  =  stopLevel * Point / pips2dbl;
   if(defaultSLpips < minGapPips)   defaultSLpips  = minGapPips;
}
void OnTick(){
   tickValue   = MarketInfo(_Symbol, MODE_TICKVALUE);    // Changes per tick.
   if(firstTick)     OnInit2();
   if(direction != 0)   move_entry(entryPrice);          // GUI visible
   if(OCOEnabled){
      enum  TriState {  TS_ON, TS_OFF, TS_UNKOWN   };
      static TriState   ocoState = TS_UNKOWN;            // No Alert on start up
      if(ocoState == TS_ON){
         if(      find_ticket(TO_BUY)  != EMPTY){
            /*void*/order_delete(TO_SELLSTOP);  ocoState = TS_OFF;
         }else if(find_ticket(TO_SELL) != EMPTY){
            /*void*/order_delete(TO_BUYSTOP);   ocoState = TS_OFF;
      }  }
      if(find_ticket(TO_BUYSTOP) != EMPTY && find_ticket(TO_SELLSTOP) != EMPTY){
         if(ocoState == TS_OFF)   Alert(_Symbol+" OCO active");
         ocoState = TS_ON;
      }else
         ocoState = TS_OFF;
   }  
}  // OnTick
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){    EventKillTimer();
   delete_gui();     direction   = 0;  // GUI not visible
   if(ShowTrades)    delete_trades();
}
//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam){
   if(      id == CHARTEVENT_KEYDOWN){
      if(      lparam == StringGetChar(BuyLine, 0) )  begin_gui(+1);
      else  if(lparam == StringGetChar(SellLine, 0))  begin_gui(-1);
      else  if(lparam == StringGetChar(CloseGUI, 0) ){
         delete_gui();  direction   = 0;  // GUI not visible
      }
   }  // CHARTEVENT_KEYDOWN
   else  if(id == CHARTEVENT_MOUSE_MOVE){
      datetime dt;   int sub_win;
      ChartXYToTimePrice(0, (int)lparam, (int)dparam, sub_win, dt, mousePrice);
   }
   else  if(direction == 0)         // GUI not visible; Ignore click,
      return;                       // Including a double click on order button.
   else  if(id == CHARTEVENT_OBJECT_DRAG){
      if(      sparam == "MMGT_RecMov"){
         orgX  = (int) ObjectGet("MMGT_RecMov", OBJPROP_XDISTANCE);
         orgY  = (int) ObjectGet("MMGT_RecMov", OBJPROP_YDISTANCE);
         create_gui();
      }
      else  if(sparam == "MMGT_Entry_Line"){
         followingPrice = false;
         move_entry(ObjectGet("MMGT_Entry_Line", OBJPROP_PRICE1) );
      }
      else if(sparam == "MMGT_TP_Line"){
         tpRatioFixed   = false;
         move_tp(ObjectGet("MMGT_TP_Line", OBJPROP_PRICE1) );
      }
      else if(sparam == "MMGT_SL_Line"){
         move_sl(ObjectGet("MMGT_SL_Line", OBJPROP_PRICE1) );
      }
   }  // Drag
   else  if(id == CHARTEVENT_OBJECT_CLICK){
      if(      sparam == "MMGT_RiskSizeButtonPlus"){
         sandboxPercent = round_nearest(sandboxPercent + 0.1, 0.1);
         fixedLotsize = false;   PlaySound("tick.wav");     create_gui();
      }
      else  if(sparam == "MMGT_RiskSizeButtonMinus"){
         sandboxPercent = round_nearest(sandboxPercent - 0.1, 0.1);
         fixedLotsize = false;   PlaySound("tick.wav");     create_gui();
      }
      else  if(sparam == "MMGT_LotSizeButtonPlus"){
         sandboxLotsize = MathMax(minimumLot,
                          MathMin(maximumLot, sandboxLotsize + lotStep) );
         fixedLotsize = true;
         PlaySound("tick.wav");     create_gui();
      }
      else  if(sparam == "MMGT_LotSizeButtonMinus"){
         sandboxLotsize = MathMax(minimumLot,
                          MathMin(maximumLot, sandboxLotsize - lotStep) );
         fixedLotsize = true;
         PlaySound("tick.wav");     create_gui();
      }
      else  if(sparam == "MMGT_RatioButton1"){
         TpRatio  = 1.0;            tpRatioFixed   = true;
         PlaySound("tick.wav");     move_tp(tpPrice);
      }
      else  if(sparam == "MMGT_RatioButton2"){
         TpRatio  = 1.5;            tpRatioFixed   = true;
         PlaySound("tick.wav");     move_tp(tpPrice);
      }
      else  if(sparam == "MMGT_RatioButton3"){
         TpRatio  = 2.0;            tpRatioFixed   = true;
         PlaySound("tick.wav");     move_tp(tpPrice);
      }
      else  if(sparam == "MMGT_RatioButton4"){
         TpRatio  = 3.0;            tpRatioFixed   = true;
         PlaySound("tick.wav");     move_tp(tpPrice);
      }
      else  if(sparam == "MMGT_Close"){
         PlaySound("tick.wav");     delete_gui();
         direction   = 0;  // GUI not visible
      }
      else  if(sparam == "MMGT_TPButton"){
         CreateTP = (!CreateTP);
         PlaySound("tick.wav");     move_tp(tpPrice);
      }
      else  if(sparam == "MMGT_SLButton"){
         CreateSL = (!CreateSL);
         if(!CreateSL)  fixedLotsize   = true;           // Use sandboxLotsize.
         PlaySound("tick.wav");     move_sl(slPrice);
      }
      else  if(sparam == "MMGT_FollowButton"){
         followingPrice = (!followingPrice);
         PlaySound("tick.wav");     move_entry(entryPrice);
      }
      else  if(sparam == "MMGT_OrderButton"){
         PlaySound("tick.wav");
         if(!newOrder() )
            ObjectSetInteger(0, "MMGT_OrderButton", OBJPROP_STATE, false);
         else{
            delete_gui();     direction   = 0;  // GUI not visible
      }  }
   }  // CHARTEVENT_OBJECT_CLICK
}  // OnChartEvent
//+------------------------------------------------------------------+
//| GUI                                                              |
//+------------------------------------------------------------------+
void begin_gui(double d){
   int iLeft,iRight; double top,bot;   GetChartLimits(iLeft, iRight, top, bot);
   double   onePct = (top - bot) * 0.01;  bot += onePct; top -= onePct;
   if(defaultSLpips < 4.0 * onePct / pips2dbl)  // USDMXN 4%=600 pips.
      defaultSLpips = 4.0 * onePct / pips2dbl;  // No overlap entry_text/sL_line

   direction      = d;
   followingPrice = mousePrice < bot || mousePrice > top;   // If Outside chart,
   if(followingPrice)   entryPrice  = d > 0 ? Ask : Bid;    // follow.
   else                 entryPrice  = mousePrice;           // Inside chart.
   tpRatioFixed   = true;
   slPrice        = entryPrice -direction* defaultSLpips * pips2dbl;
   tpPrice        = entryPrice +direction* defaultSLpips * pips2dbl * TpRatio;
   sandboxPercent = InitialPercent;
   sandboxLotsize = minimumLot;        fixedLotsize   = !CreateSL;
   move_entry(entryPrice);
}
void move_entry(double price){
   if(followingPrice){
      orderType   = direction> 0 ? OP_BUY : OP_SELL;
      price       = direction> 0 ? Ask : Bid;
   }
   else{
      double   minGap   = stopLevel * Point;
      double   upper =  Ask + minGap;
      double   lower =  Bid - minGap;
      if(price > (upper+lower)/2.0){
         orderType   = direction> 0 ? OP_BUYSTOP : OP_SELLLIMIT;
         if(price < upper) price = upper;
      }
      else{
         orderType   = direction> 0 ? OP_BUYLIMIT : OP_SELLSTOP;
         if(price > lower) price = lower;
   }  }
   entryPrice  = normalize_price(price);
   move_sl(slPrice);
}
void move_sl(double price){
   double   minGap   = stopLevel * Point;
   if( (entryPrice - price)*direction < minGap)
      price = entryPrice -direction * minGap;
   slPrice  = normalize_price(price, -direction);
   move_tp(tpPrice);
}
void move_tp(double price){
   double   minGap   = stopLevel * Point;
   if(tpRatioFixed)
      price = entryPrice + (entryPrice - slPrice) * TpRatio;
   if( (price - entryPrice)*direction < minGap)
      price = entryPrice +direction * minGap;
   tpPrice  = normalize_price(price, +direction);
   create_gui();
}
void create_gui(void){
   double   sl       = MathAbs(slPrice - entryPrice),
            slPips   =        (slPrice - entryPrice) / pips2dbl,
            tp       = MathAbs(tpPrice - entryPrice),
            tpPips   =        (tpPrice - entryPrice) / pips2dbl;
   defaultSLpips  = sl / pips2dbl;
   // RISK = Account Balance * percent/100
   // RISK = OrderLots * (|OrderOpenPrice - OrderStopLoss| * DeltaValuePerlot
   //                    + CommissionPerLot)
   // (Note OOP-OSL includes the SPREAD)
   double   dVpL  = tickValue / tickSize; // DeltaValuePerlot

   string   USD      = AccountInfoString(ACCOUNT_CURRENCY);
   string   balance  = RiskBasis == Balance  ? "Balance" : "Equity";
   double   money    = AccountInfoDouble(RiskBasis == Balance ? ACCOUNT_BALANCE
                                                              : ACCOUNT_EQUITY);

   double   risk     = money * InitialPercent / 100.0;
   double   maxLots  = normalize_lots( risk / (sl * dVpL + CommissionPerLot) );  // div 0
                                          // Percentage
   double   maxBet   =              maxLots * (sl * dVpL + CommissionPerLot);
   double   maxWin   =              maxLots *  tp * dVpL;

   double   sbRisk   = money * sandboxPercent / 100.0;
   if(!fixedLotsize)
      sandboxLotsize = normalize_lots(sbRisk / (sl * dVpL + CommissionPerLot) );
   double   sbBet =           sandboxLotsize * (sl * dVpL + CommissionPerLot);
   if(fixedLotsize){
      sandboxPercent = round_nearest(sbBet / money * 100.0, 0.01);
      sbRisk         = money * sandboxPercent / 100.0;;
   }
   double   sbWin =           sandboxLotsize *  tp * dVpL;

   string   text1    = StringFormat(
                     "Risk         : %.1f%% = %.2f %s / %s %.2f %s",
                     InitialPercent, risk, USD, balance, money, USD);
   string   text7    = StringFormat(
                     "Risk         : %.2f%% = %.2f %s / %s %.2f %s",
                     sandboxPercent, sbRisk, USD, balance, money, USD);

   string   text2    = "Ratio        : no TP";
   string   text4    = "TP           : no TP";
   string   text10   = "TP           : no TP";
   if(CreateTP){
      if(!CreateSL)  text2 =              "Ratio        : no SL";
      else{          text2 = StringFormat("Ratio        : 1:%.2f",
                                          tp / MathMax(Point, sl) );
                     text4 = StringFormat("TP           : [%s pips  %.2f %s]",
                           pips_as_string(tpPips), maxWin, USD);
                  text10   = StringFormat("TP           : [%s pips  %.2f %s]",
                           pips_as_string(tpPips), sbWin, USD);
   }  }
   string   text3    = "SL           : no SL";     color color3   = ColorText;
   string   text5    = "Lot Size Max : no SL";     color color5   = clrYellow;
   string   text9    = "SL           : no SL";
   string   text8    = StringFormat("Lot Size     : %s",
                                    lots_as_string(sandboxLotsize) );
   color    color8   =  sandboxLotsize < minimumLot
                     || sandboxLotsize > maximumLot ? clrRed : clrYellow;
   if(CreateSL){
      text3 = StringFormat("SL           : [%s pips  %.2f %s]",
                           pips_as_string(slPips), maxBet, USD);
      text9 = StringFormat("SL           : [%s pips  %.2f %s]",
                           pips_as_string(slPips), sbBet, USD);
      if(sl < (Ask - Bid) *2.0)  color3   = clrRed;
      text5    = StringFormat("Lot Size Max : %s", lots_as_string(maxLots) );
                                          // Percentage
      color5   =  maxLots < minimumLot
               || maxLots > maximumLot ? clrRed : ColorText;
      if(sandboxLotsize <= maxLots)    color8   = color5;
      /* MaximumLot                                         Broker limits
         maximumLot  = MarketInfo(_Symbol, MODE_MAXLOT);
         minimumLot  = MarketInfo(_Symbol, MODE_MINLOT);
         sandboxLotsize <= maxLots                          Percentage Risk
         tbd                                                Margin Call
      */
   }
   // Make the GUI
   delete_gui();

   // Create the lines in selectable order, entry, tp, SL!.
   double   pips  = (entryPrice - Bid) / pips2dbl;
   string   text  = StringFormat("%s / %s Pips from actual price",
                           price_as_string(entryPrice), pips_as_string(pips) );
   create_hLine("MMGT_Entry_Line", entryPrice, ColorEntry);
   create_text( "MMGT_Entry_Text", entryPrice, text, ColorEntry);

   string   bs = direction > 0 ? "Buy" : "Sell";
   if(CreateTP){
      pips  = (tpPrice - entryPrice) / pips2dbl;
      text  = StringFormat("TP at %s / %s Pips from %s",
                           price_as_string(slPrice), pips_as_string(pips), bs);
      create_hLine("MMGT_TP_Line", tpPrice, ColorTP);
      create_text( "MMGT_TP_Text", tpPrice, text, ColorTP);
   }
   if(CreateSL){
      pips  = (slPrice - entryPrice) / pips2dbl;
      text  = StringFormat("SL at %s / %s Pips from %s",
                           price_as_string(slPrice), pips_as_string(pips), bs);
      create_hLine("MMGT_SL_Line", slPrice, ColorSL);
      create_text( "MMGT_SL_Text", slPrice, text, ColorSL);
   }
   if(!TransparentBox){
      create_rect("MMGT_RectLabel", -10, -10, 480, 240);
      // Default tip
      ObjectSetString(0,"MMGT_RectLabel", OBJPROP_TOOLTIP, WindowExpertName() );
   }
   string   text0    = StringFormat(
                     "             : PIP = %s", price_as_string(pips2dbl) );
   create_label("MMGT_Line0", 0, -5, text0, text0);

   create_rect("MMGT_RecMov", 0, 0, 10, 10, 3);
   ObjectSetInteger(0, "MMGT_RecMov", OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, "MMGT_RecMov", OBJPROP_SELECTED, true);
   ObjectSetInteger(0, "MMGT_RecMov", OBJPROP_ZORDER, Priority_Buttons);

   text  = StringFormat("Risk %% = Risk %s / Account Size", USD);
   create_label("MMGT_Line1", 0, 10, text1, text);
   create_label("MMGT_Line2", 0, 25, text2, "TP:SL Ratio");
      button_create("MMGT_RatioButton1", 180, 27, 12, 12,
                                            "1", "ratio 1:1", clrNONE, 8);
      button_create("MMGT_RatioButton2", 195, 27, 12, 12,
                                            "2", "ratio 1:1.5", clrNONE, 8);
      button_create("MMGT_RatioButton3", 210, 27, 12, 12,
                                            "3", "ratio 1:2", clrNONE, 8);
      button_create("MMGT_RatioButton4", 225, 27, 12, 12,
                                            "4", "ratio 1:3", clrNONE, 8);
   create_label("MMGT_Line3", 0, 40, text3, "SL pips & value", color3);
   create_label("MMGT_Line4", 0, 55, text4, "TP pips & value");
   create_label("MMGT_Line5", 0, 70, text5, "Lot Size Max", color5);
   create_label("MMGT_Line6", 0, 85,
                                 "--SandBox-/-OpenOrder---------------------",
                                 "SandBox Section");
   create_label("MMGT_Line7", 0, 100, text7, "Change the risk");
      button_create("MMGT_RiskSizeButtonPlus", 80, 102, 10, 10,
                                                  "+", "increase the risk");
      if(sandboxPercent > 0.1)
      button_create("MMGT_RiskSizeButtonMinus", 90, 102, 10, 10,
                                                  "-", "decrease the risk");
   create_label("MMGT_Line8", 0, 115, text8, "Lot Size you want", color8);
      if(sandboxLotsize < maximumLot)
      button_create("MMGT_LotSizeButtonPlus", 80, 117, 10, 10,
                                                 "+", "increase lot size");
      if(sandboxLotsize > minimumLot)
      button_create("MMGT_LotSizeButtonMinus", 90, 117, 10, 10,
                                                  "-", "decrease lot size");
   create_label("MMGT_Line9",  0, 130, text9,  "SL", color3);
   create_label("MMGT_Line10", 0, 145, text10, "TP");
   create_label("MMGT_Line11", 0, 160,
                     "    Show TP Line       Show SL Line       Follow price",
                     "Tp/SL line On/Off and follow price");
      button_create("MMGT_TPButton", 0, 160, 25, 15,
                                        CreateTP ? "On"     : "Off",
                                        "Tp line On/Off",
                                        CreateTP ? clrGreen : clrRed);
      button_create("MMGT_SLButton", 150, 160, 25, 15,
                                        CreateSL ? "On"     : "Off",
                                        "TL line On/Off",
                                        CreateSL ? clrGreen : clrRed);
      button_create("MMGT_FollowButton", 300, 160, 25, 15,
                                        followingPrice ? "Yes"    : "No",
                                        "Buy/Sell line follows the market",
                                        followingPrice ? clrGreen : clrRed);
//Line 12 or Order button
   if(color8 == clrRed)
      create_label("MMGT_Line12", 0, 185,
                                     "Lot Size outside limits!",
                                     "Lot Size outside limits", clrNONE, 8);
   else  if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      create_label("MMGT_Line12", 0, 185,
             "Check if automated trading is allowed in the terminal settings!",
             "Auto-trading not allowed", clrNONE, 8);
   else{
      string opText[] = {"Buy",  "Sell",  "Buy Limit",   "Sell Limit",
                                          "Buy Stop",    "Sell Stop"};
      text  = StringFormat("Order %s %s Lot%s", opText[orderType],
                           lots_as_string(sandboxLotsize),
                           sandboxLotsize > 1.0 ? "s" : "");
      button_create("MMGT_OrderButton", 0, 180, 190, 20, text,
                                           "Order used Sandbox parameter");
   }
      button_create("MMGT_Close", 416, 180, 50, 20, "Close",
                                     "Close this box and all lines");
   text  = StringFormat(
               "Min Lot: %.2f / Max Lot: %.2f / Step: %.2f / SL TP limit: %s",
               minimumLot, maximumLot, lotStep,
               pips_as_string(stopLevel*Point/pips2dbl, "") );
   create_label("MMGT_Line13", 0, 210, text, "Broker limits", clrNONE, 8);
}  // create_gui
void delete_gui(void){  ObjectsDeleteAll(0, "MMGT_"); }
//+------------------------------------------------------------------+
//| Order button pressed                                             |
//+------------------------------------------------------------------+
bool  newOrder(){    // USDMXN spread = 69.6 pips
   RefreshRates();
   int slippage   = int( (Ask - Bid) * 2.0 / _Point);
   if(!CreateTP)  tpPrice = 0;
   if(!CreateSL)  slPrice = 0;
   int ticket  = OrderSend(_Symbol, orderType, sandboxLotsize, entryPrice,
                           slippage, slPrice, tpPrice, "OGT", MagicNumber, 0,
                           clrNONE);
   if(ticket < 0){   // No split www.mql5.com/en/forum/216346#comment_5820584
      Alert(errortext(_LastError) );
      return false;
   }
   PlaySound("ok.wav");
   return true;
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string errortext(int errorcode){
   switch(errorcode){
   case   1: return "No result";
   case   2: return "Common error";
   case   3: return "Invalid trade parameters";
   case   4: return "Server busy";
   case   5: return "Old version";
   case   6: return "No connection";
   case   7: return "Not enough rights";
   case   8: return "Too frequent requests";
   case   9: return "Malfunctional trade";
   case  64: return "Account disabled";
   case  65: return "Invalid account";
   case 128: return "Trade timeout";
   case 129: return "Invalid price";
   case 130: return "Invalid stops";
   case 131: return "Invalid trade volume";
   case 132: return "Market is closed";
   case 134: return "Not enough money";
   case 135: return "Price changed";
   case 136: return "Off quotes";
   case 137: return "Broker is busy";
   case 138: return "Requote";
   case 139: return "Order is locked";

   case 141: return "Too many requests";
   case 145: return "Modification denied because order is too close to market";
   case 147: return "Expirations are denied by broker";
   case 148: return "The amount of open and pending orders has reached "
                     "the limit set by the broker";
   case 149: return "An attempt to open an order opposite to the existing one "
                     "when hedging is disabled";
   case 150: return "An attempt to close an order contravening the FIFO rule";
   default:  return StringFormat("Error %i", errorcode);
   }  // switch
   //NOTREACHED
}
double   normalize_price(double p, double d=0.0){
   if(d > 0)   return round_up(p,      tickSize);
   if(d < 0)   return round_down(p,    tickSize);
               return round_nearest(p, tickSize);
}
double   normalize_lots(double lots){
   return round_down(lots, lotStep);
   return lots;
}
string   lots_as_string( double lots){ return DoubleToStr(lots, digitsLots);   }
string   price_as_string(double price){return DoubleToStr(price, _Digits);     }
string   pips_as_string( double pips, string plusSign="+"){
   return to_signed_fixed(pips, digitsPip, plusSign);                          }
string   to_signed_fixed(double value, int nDecimals, string plusSign="+"){
   if(value < 0.) plusSign = "";
   return plusSign + DoubleToStr(value, nDecimals);
}
string            as_string(Trade_Operation op=WRONG_VALUE){
   if(op == WRONG_VALUE)   op = (Trade_Operation)OrderType();
   string TO_xxx = EnumToString(op);                           // TO_XXX
   return StringSubstr(TO_xxx, 3);                             // XXX
}
bool     select_order(int iWhat, int eSelect, int ePool=MODE_TRADES){
    if(!OrderSelect(iWhat, eSelect, ePool)   ) return false;
    if(OrderMagicNumber() != MagicNumber     ) return false;   // \ Extern
    if(OrderSymbol()      != _Symbol         ) return false;   // / variables.
    if(ePool != MODE_HISTORY                 ) return true;
    return OrderType() <= OP_SELL;  // Avoid cr/bal forum.mql4.com/32363#325360
                                    // Never select canceled orders.
}
int      find_ticket(Trade_Operation op, int ePool=MODE_TRADES){
   int   iPos  = ePool == MODE_TRADES ? OrdersTotal() : OrdersHistoryTotal();
   while(iPos > 0)   if(select_order(--iPos, SELECT_BY_POS, ePool)
                     && OrderType() == op )  return OrderTicket();
   return EMPTY;
}
bool     order_delete(Trade_Operation op){
   int      ticket   = find_ticket(op);   if(ticket == EMPTY)  return false;
   bool     result   = OrderDelete(ticket);
   if(!result) Alert(StringFormat("OrderDelete(%i):%i", ticket, _LastError) );
   return result;
}
double   round_down(    double v, double to){   return to * MathFloor(v / to); }
double   round_up(      double v, double to){   return to * MathCeil( v / to); }
double   round_nearest( double v, double to){   return to * MathRound(v / to); }
int      digits_in(double d){
   int digits  = 0;
   while(d - int(d) >  1.E-8){ d *= 10.0; ++digits; }
  return digits;
}
                                                         #define WINDOW_MAIN 0
void     GetChartLimits(int&iLeft, int&iRight, double&top, double&bot,int iW=0){
      /* MT4 build 445: In the tester (visual mode,) on the first tick, these
       * routines return left=100, right=37 (depends on default bar scaling.)
       * This is what the chart looks like when you maximize it while it is
       * generating the FXT file. On ticks after that, it appears like the
       * left/right are correct but the hi/lo are one tick behind the displayed
       * chart. On the start of a new bar, the hi/lo can be off when a recent
       * extreme drops off but the scale hasn't resized. I tried calling
       * WindowRedraw() first but that did not change results. I don't know
       * about live charts.                                                   */
   top      = WindowPriceMax(iW);   iLeft    = WindowFirstVisibleBar();
   bot      = WindowPriceMin(iW);   iRight   = iLeft-WindowBarsPerChart();
   if(top-bot < pips2dbl)  top    = bot+pips2dbl;     // Avoid scroll bug / div0
   if(iRight < 0)          iRight = 0;                // Chart is shifted.
}  // GetChartLimits
//+------------------------------------------------------------------+
//| Create rectangle label                                           |
//+------------------------------------------------------------------+
void create_rect(string name, int offX, int offY, int width, int height,
                 int line_width=1){
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    orgX + offX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    orgY + offY);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      ColorBox);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        ColorText);
   ObjectSetInteger(0, name, OBJPROP_STYLE,        STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,        line_width);
   ObjectSetInteger(0, name, OBJPROP_BACK,         false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,     false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,       false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,       Priority_Box);
}  // create_rect
//+------------------------------------------------------------------+
//| Create horizontal line                                           |
//+------------------------------------------------------------------+
void create_hLine(string   name,                   // line name
                  double   hprice,                 // line price
                  color    clr){                   // line color
   ObjectCreate(name, OBJ_HLINE, 0, 0, hprice);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,        LineStyle);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,        LineWidth);
   ObjectSetInteger(0, name, OBJPROP_BACK,         false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,     true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,       false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,       Priority_Lines);
}  // create_hLine
//+------------------------------------------------------------------+
//| Create button                                                    |
//+------------------------------------------------------------------+
void button_create(string name, int offX, int offY, int width, int height,
                  string text, string tip, color clr=clrNONE, int font_size=10){
   if(clr == clrNONE)   clr   = ColorText;
   ObjectCreate(name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,    orgX + offX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,    orgY + offY);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        height);

   ObjectSetString( 0, name, OBJPROP_FONT,         "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     font_size);
   ObjectSetString( 0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);  // Text color
   ObjectSetString( 0, name, OBJPROP_TOOLTIP, tip);

   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      C'236, 233, 216');
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        clrBlack);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrNONE);
   ObjectSetInteger(0, name, OBJPROP_BACK,         false);
   //--- enable (true) or disable (false) the mode of moving the button by mouse
   ObjectSetInteger(0, name, OBJPROP_STATE,        false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED,     false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,       false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,       Priority_Buttons);
}  // button_create
//+------------------------------------------------------------------+
//| Create label.                                                    |
//+------------------------------------------------------------------+
void create_label(string name, int offX, int offY, string text, string tip,
                  color clr=clrNONE, int font_size=10){
   if(clr == clrNONE)   clr   = ColorText;
   ObjectCreate(name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, orgX + offX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, orgY + offY);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetText(name, text, font_size, "Courier New", clr);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}  // create_label
//+------------------------------------------------------------------+
//| Create text object.                                              |
//+------------------------------------------------------------------+
void create_text(string name, double price, string text, color clr,
                 int font_size=10){
   ObjectCreate(name, OBJ_TEXT, 0, Time[2], price);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   ObjectSetText(name, text, font_size, "Courier New", clr);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, text);
}  // create_text
//+------------------------------------------------------------------+
//| Create Trend line                                                |
//+------------------------------------------------------------------+
void create_tLine(string   name,
                  datetime time1,   double   price1,
                  datetime time2,   double   price2,
                  color    clr,
                  ENUM_LINE_STYLE   style=STYLE_DOT){
   ObjectCreate(name, OBJ_TREND, WINDOW_MAIN, time1, price1, time2, price2);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE,        style);
   ObjectSetInteger(0, name, OBJPROP_RAY,          false);
}
//+------------------------------------------------------------------+
//| Create Arrow                                                     |
//+------------------------------------------------------------------+
void create_arrow(string   name,
                  datetime time, double   price,
                  int      code,
                  color    clr){
   ObjectCreate(name, OBJ_ARROW, WINDOW_MAIN, time, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        clr);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE,    code);
}
//+------------------------------------------------------------------+
//| Create Order result                                              |
//+------------------------------------------------------------------+
void create_trades(bool doAlert){  // Order is selected.
      int      ot          = OrderType();
   color    clr         = ot == OP_BUY ? Blue : Red;
   string   op          = as_string( (Trade_Operation)ot);

   datetime from        = OrderOpenTime(),   to    = OrderCloseTime();
   double   oop         = OrderOpenPrice(),  ocp   = OrderClosePrice();
   string   open        = price_as_string(oop);
   string   close       = price_as_string(ocp);

   string   lots        = lots_as_string(OrderLots() );
   int      ticket      = OrderTicket();

   string   tLine = StringFormat("#%i %s -> %s", ticket, open, close);
   if(doAlert && ObjectFind(tLine) < 0)
      Alert(StringFormat("closed %i on %s",ticket,_Symbol));   // expert.wav;
   /*void*/ create_tLine(tLine,
                         from, oop, to, ocp, clr);
   /*void*/ create_arrow(StringFormat("#%i %s %s %s at %s",
                                      ticket, op, lots, _Symbol, open),
                         from, oop, 1, clr);
   /*void*/ create_arrow(StringFormat("#%i %s %s %s at %s close at %s",
                                      ticket, op, lots, _Symbol, open, close),
                         to, ocp, 3, Goldenrod);
}
void     delete_trades(void){ ObjectsDeleteAll(0, "#"); }
//+------------------------------------------------------------------+
