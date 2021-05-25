#property strict

#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

CAccountInfo m_account;

const int LOG_NONE  = 0;
const int LOG_ERROR = 1;
const int LOG_WARN  = 2;
const int LOG_INFO  = 3;
const int LOG_DEBUG = 4;

double getAdjustedPoint(string symbol) {
   //--- tuning for 3 or 5 digits
   int digits_adjust=1;
   if(SymbolInfoInteger(symbol,SYMBOL_DIGITS) == 3 || SymbolInfoInteger(symbol,SYMBOL_DIGITS) == 5)
      digits_adjust=10;
      
   double m_adjusted_point = SymbolInfoDouble(symbol,SYMBOL_POINT) * digits_adjust;   
   printHelper(LOG_DEBUG, StringFormat("_Point value is %f",m_adjusted_point));
   
   return m_adjusted_point;
}

double getNormalizedVolume(double lot, string symbol) {
   //--- normalize and check limits
   double stepvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   lot=stepvol*NormalizeDouble(lot/stepvol,0);

   double minvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(lot<minvol)
      lot=minvol;

   double maxvol=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   if(lot>maxvol)
      lot=maxvol;

   return lot;
}

void placeBuyOrder(CTrade &m_trade, double sl, double tp, double lot, string symbol, string comment) {
   double price = SymbolInfoDouble(symbol,SYMBOL_ASK);

   sl = NormalizeDouble(sl,SymbolInfoInteger(symbol,SYMBOL_DIGITS));
   double volume = getNormalizedVolume(lot, symbol);
   
   //BEGIN Calc margin
   double margin = 0.00;
   ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
   OrderCalcMargin(orderType, symbol,volume,price,margin);
   //END Calc margin
   
   printHelper(LOG_INFO, StringFormat("About to place buy order of volume %f and amount %f ", volume, margin));
   m_trade.Buy(volume,symbol,price,sl,tp,comment);
}

void placeSellOrder(CTrade &m_trade, double sl, double tp, double lot, string symbol, string comment) {
   double price = SymbolInfoDouble(symbol,SYMBOL_BID);

   sl = NormalizeDouble(sl,SymbolInfoInteger(symbol,SYMBOL_DIGITS));
   double volume = getNormalizedVolume(lot, symbol);
   
   //BEGIN Calc margin
   double margin = 0.00;
   ENUM_ORDER_TYPE orderType = ORDER_TYPE_SELL;
   OrderCalcMargin(orderType, symbol,volume,price,margin);
   //END Calc margin
   
   printHelper(LOG_INFO, StringFormat("About to place sell order of volume %f and amount %f", volume, margin));
   m_trade.Sell(volume,symbol,price,sl,tp,comment);
}

void printHelper(int level, string formattedText) {
   int logLevel = GlobalVariableGet("LOG_LEVEL");
   if(level <= logLevel) {
      Print(formattedText);
   }
}