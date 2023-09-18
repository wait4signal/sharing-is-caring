//+------------------------------------------------------------------+
/*
    TradeUtil.mqh 

    Copyright (C) 2021  Bheki Gabela

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
//+------------------------------------------------------------------+

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

   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   double volume = getNormalizedVolume(lot, symbol);
   
   //BEGIN Calc margin
   double margin = 0.00;
   ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
   ResetLastError();
   if (!OrderCalcMargin(orderType, symbol, volume, price, margin)) {
      printHelper(LOG_ERROR, "OrderCalcMargin error: " + IntegerToString(GetLastError()));
      return;
   }
   //END Calc margin
   
   printHelper(LOG_INFO, StringFormat("About to place buy order of volume %f and amount %f ", volume, margin));
   m_trade.Buy(volume,symbol,price,sl,tp,comment);
}

void placeSellOrder(CTrade &m_trade, double sl, double tp, double lot, string symbol, string comment) {
   double price = SymbolInfoDouble(symbol,SYMBOL_BID);

   sl = NormalizeDouble(sl, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   double volume = getNormalizedVolume(lot, symbol);

   //BEGIN Calc margin
   double margin = 0.00;
   ENUM_ORDER_TYPE orderType = ORDER_TYPE_SELL;
   ResetLastError();
   if (!OrderCalcMargin(orderType, symbol, volume, price, margin)) {
      printHelper(LOG_ERROR, "OrderCalcMargin error: " + IntegerToString(GetLastError()));
      return;
   }
   //END Calc margin
   
   printHelper(LOG_INFO, StringFormat("About to place sell order of volume %f and amount %f", volume, margin));
   m_trade.Sell(volume,symbol,price,sl,tp,comment);
}

void printHelper(int level, string formattedText) {
   // Set default log level to show errors
   int logLevel = LOG_ERROR;
   if (GlobalVariableCheck("LOG_LEVEL")) {
      logLevel = (int)GlobalVariableGet("LOG_LEVEL");
   }

   if(level <= logLevel) {
      Print(formattedText);
   }
}