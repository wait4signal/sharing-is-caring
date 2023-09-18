//+------------------------------------------------------------------+
/*                            
    Sharing-Is-Caring.mq5 

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

#include <Expert\Expert.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

// Required for compiling in wine on linux
// #define _LINUX_
#ifdef _LINUX_
#include <TradeUtil.mqh>
#else
#include "TradeUtil.mqh"
#endif

enum ENUM_COPY_MODE {
   PROVIDER, 
   RECEIVER
};

enum ENUM_LOT_SIZE {
   SAME_AS_PROVIDER,
   PROPORTIONAL_TO_BALANCE,
   PROPORTIONAL_TO_FREE_MARGIN
};

//--- Global Variables
/*
LOG_LEVEL                        //Sets log level: LOG_NONE  = 0; LOG_ERROR = 1; LOG_WARN  = 2; LOG_INFO  = 3; LOG_DEBUG = 4;
*/

//--- input parameters
input ENUM_COPY_MODE COPY_MODE = RECEIVER; // Operating mode
input int PROCESSING_INTERVAL_MS = 500;    // Processing interval (ms)
input group "Monitoring";
input string HEARTBEAT_URL = "";            // Heart beat URL
input ulong HEARTBEAT_INTERVAL_MINUTES = 5; // Heart beat interval (minutes)
input group "Provider";
input bool REMOTE_FTP_PUBLISH = false; // Publish to remote FTP
input group "Receiver";
input ulong PROVIDER_ACCOUNT;                           // Provider account number
input int PRICE_DEVIATION = 50;                         // Price deviation
input bool COPY_IN_PROFIT = false;                      // Copy trades in profit
input ulong EXCLUDE_OLDER_THAN_MINUTES = 5;             // Exclude trades older than X minutes
input bool COPY_BUY = true;                             // Copy buy trades
input bool COPY_SELL = true;                            // Copy sell trades
input ENUM_LOT_SIZE LOT_SIZE = PROPORTIONAL_TO_BALANCE; // Trade volume mode
input bool USE_LEVERAGE_FOR_LOT_CALCULATION = true;     // Use leverage for volume calculation
input double MIN_AVALABLE_FUNDS_PERC = 0.20;            // Minimum available funds percentage
input string EXCLUDE_TICKETS = "";                      // Exclude tickets
input string INSTRUMENT_MATCH = "";                     // Match instruments
input bool ALERT_MULTIPLE_LOSERS_CLOSE = true;          // Alert email on multiple losing trades
// input bool     COPY_SL=true;
// input bool     COPY_TP=true;
input group "Remote Copy";
input bool REMOTE_HTTP_DOWNLOAD = false; // Remote HTTP download
input string REMOTE_FILE_URL = "";       // Remote file URL
input string REMOTE_USERNAME = "";       // Remote user name
input string REMOTE_PASSWORD = "";       // Remote password

CTrade       sic_trade; 

int FILE_RETRY_MS = 50;
int FILE_MAXWAIT_MS = 500;

ulong lastHeartbeatTime = 0;

string positionsFileName;

int prRecordCount;
datetime prTimeLocal;
datetime prTimeGMT;
ulong prAccountNumber;
double prAccountBalance;
double prAccountEquity;
string prAccountCurrency;
int prAccountLeverage;
int prMarginMode;
long prTradeServerGMTOffset;

struct PositionData {
    int seq;
    ulong positionMagic;
    long positionTicket;
    ulong positionOpenTime;
    int positionType;
    double positionVolume;
    double positionPriceOpen;
    double positionSL;
    double positionTP;
    double positionProfit;
    string positionSymbol;
    string positionComment;
    int positionLeverage;
};

PositionData prRecords[];
PositionData recPositions[];

int OnInit() {
   //Input validations   
   if(RECEIVER == COPY_MODE && PROVIDER_ACCOUNT < 1000) {
      printHelper(LOG_ERROR, "Provider Account is required and should be at least 4 digits long.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   
   ulong fileAccount = AccountInfoInteger(ACCOUNT_LOGIN);
   if(RECEIVER == COPY_MODE) {
      fileAccount = PROVIDER_ACCOUNT;
   }
   positionsFileName = "Sharing-Is-Caring\\"+ IntegerToString(fileAccount) +"-positions.csv";
   
   EventSetMillisecondTimer(PROCESSING_INTERVAL_MS);
   
   return(INIT_SUCCEEDED);
 }

void OnDeinit(const int reason) {
   EventKillTimer();
}

void OnTick() {
   //-- Nothing to do
}

void OnTimer() {
   resetValues();
   if(PROVIDER == COPY_MODE) {
      //Write all current positions to a file
      writePositions();
      //Share signals via ftp
      if(REMOTE_FTP_PUBLISH) {
         SendFTP(positionsFileName);
      }
   } else if(RECEIVER == COPY_MODE) {
      //Download signals from web and put in same location as local provider
      if(REMOTE_HTTP_DOWNLOAD) {
         downloadFile();
      }
      
      //Read from file and save to file array
      readPositions();
      
      if(prMarginMode != AccountInfoInteger(ACCOUNT_MARGIN_MODE)) {
         printHelper(LOG_ERROR, StringFormat("Can't copy between different MARGIN MODE, Provider is %d while Receiver is %d .", prMarginMode, AccountInfoInteger(ACCOUNT_MARGIN_MODE)));
         return;
      }
      
      //Get existing positions previously received from this provider
      int matchesCount = 0;
      int posTotal=PositionsTotal();
      for(int i= 0; i < posTotal; i++) {
         PositionGetSymbol(i);
         
         //Skip if in excluded ticket list
         if(StringFind(EXCLUDE_TICKETS,"["+ IntegerToString(PositionGetInteger(POSITION_TICKET)) +"]") != -1) { //-1 means no match
            continue;
         }
         
         ulong positionMagic = PositionGetInteger(POSITION_MAGIC);
         if(prAccountNumber == positionMagic) {
            matchesCount++;
            ArrayResize(recPositions,matchesCount);
            PositionData positionData;
            
            positionData.seq = matchesCount-1;
            positionData.positionMagic = positionMagic;
            positionData.positionTicket = PositionGetInteger(POSITION_TICKET);
            positionData.positionOpenTime = PositionGetInteger(POSITION_TIME_MSC);
            positionData.positionType = (int)PositionGetInteger(POSITION_TYPE);
            positionData.positionVolume = PositionGetDouble(POSITION_VOLUME);
            positionData.positionPriceOpen = PositionGetDouble(POSITION_PRICE_OPEN);
            positionData.positionSL = PositionGetDouble(POSITION_SL);
            positionData.positionTP = PositionGetDouble(POSITION_TP);
            positionData.positionProfit = PositionGetDouble(POSITION_PROFIT);
            positionData.positionSymbol = PositionGetString(POSITION_SYMBOL);
            positionData.positionComment = PositionGetString(POSITION_COMMENT);
            
            recPositions[matchesCount-1] = positionData;
         }
      }
      
      //Update receiver positions based on what's in file
      updatePositions();
      //Close positions that are no longer in the file
      closePositions();
   }
   
   if(StringLen(HEARTBEAT_URL) > 4) { //Surely can't have url shorter than this...
      processHeartbeat();
   }
}

void resetValues() {
   prRecordCount = 0;
   prTimeLocal = 0;
   prTimeGMT = 0;
   prAccountNumber = 0;
   prAccountBalance = 0;
   prAccountEquity = 0;
   prAccountCurrency = "";
   prAccountLeverage = 0;
   prMarginMode = 0;
   prTradeServerGMTOffset = 0;

   ArrayResize(prRecords,0);
   ArrayResize(recPositions,0);
}

bool updatePositions() {
   sic_trade.SetExpertMagicNumber(prAccountNumber);
   sic_trade.SetMarginMode();
   sic_trade.SetDeviationInPoints(PRICE_DEVIATION);
      
   int prRecordsSize = ArraySize(prRecords);
   for(int i=0; i<prRecordsSize; i++) {
      PositionData prRecord = prRecords[i];
      
      string positionSymbol = prRecord.positionSymbol;
      int instrMatch = StringFind(INSTRUMENT_MATCH,"["+positionSymbol+"=");
      if(instrMatch != -1) { //-1 means no match
         int instrStartPos = instrMatch + StringLen(positionSymbol) + 2;
         int instrEndPos = StringFind(INSTRUMENT_MATCH,"]",instrMatch);
         positionSymbol = StringSubstr(INSTRUMENT_MATCH,instrStartPos,(instrEndPos-instrStartPos));
         printHelper(LOG_DEBUG, StringFormat("Found instrument match from [%s] to [%s]", prRecord.positionSymbol, positionSymbol));
      }
      
      //Print error and skip if symbol does not exist
      bool is_custom=false;
      if(!SymbolExist(positionSymbol,is_custom)) {
         printHelper(LOG_ERROR, StringFormat("Can't copy trade %d as symbol %s does not exist...try setting an INSTRUMENT_MATCH config", prRecord.positionTicket, positionSymbol));
         continue;
      }
      
      sic_trade.SetTypeFillingBySymbol(positionSymbol);
      
      //Skip if in excluded ticket list
      if(StringFind(EXCLUDE_TICKETS,"["+ IntegerToString(prRecord.positionTicket) +"]") != -1) { //-1 means no match
         continue;
      }
      
      bool exists = false;
      PositionData recPosition;
      int recPositionsSize = ArraySize(recPositions);
      for(int i=0; i<recPositionsSize; i++){
         if((GlobalVariableGet("VOL-"+ IntegerToString(recPositions[i].positionTicket) +"-"+ IntegerToString(prRecord.positionTicket)) != 0) || (StringFind(recPositions[i].positionComment,"TKT="+ IntegerToString(prRecord.positionTicket)) != -1)) { //-1 means no match
            exists = true;
            recPosition = recPositions[i];
            break;
         }
      }
      
      if(exists) {
         if(recPosition.positionSL != prRecord.positionSL || recPosition.positionTP != prRecord.positionTP) {
            sic_trade.PositionModify(recPosition.positionTicket,prRecord.positionSL,prRecord.positionTP);
         }
         //Handle partial close or add(if vol increases then it must be netting account because hedge would be a new deal)
         double prCurrentVol = GlobalVariableGet("VOL-"+ IntegerToString(recPosition.positionTicket) +"-"+ IntegerToString(prRecord.positionTicket)); //First try using previous partial close balance if exists
         if(prCurrentVol == 0) {
            int volStartPos = StringFind(recPosition.positionComment,"VOL=") + 4;
            int volEndPos = StringFind(recPosition.positionComment,"]");
            prCurrentVol = StringToDouble(StringSubstr(recPosition.positionComment,volStartPos,(volEndPos-volStartPos)));
            printHelper(LOG_DEBUG, StringFormat("Current pr volume read starts at %d and ends at %d, value is %d", volStartPos, volEndPos, prCurrentVol));
         }
         double prVolDifference = MathAbs(prRecord.positionVolume - prCurrentVol);
         double volRatio = prVolDifference/prCurrentVol;
         double recVolDifference = recPosition.positionVolume * volRatio;
         recVolDifference = getNormalizedVolume(recVolDifference,positionSymbol);
         printHelper(LOG_DEBUG, StringFormat("prVolDifference is %d, using volRatio of %d we get recVolDifference of %d", prVolDifference, volRatio, recVolDifference));
         string comment = "[TKT="+ IntegerToString(prRecord.positionTicket) +",VOL="+DoubleToString(prRecord.positionVolume,2)+"]";
         if(prRecord.positionVolume > prCurrentVol) {//Vol size increased
            if(ACCOUNT_MARGIN_MODE_RETAIL_NETTING == AccountInfoInteger(ACCOUNT_MARGIN_MODE)) {
               if(prRecord.positionType == 0 && COPY_BUY) {
                  placeBuyOrder(sic_trade, prRecord.positionSL, prRecord.positionTP, recVolDifference, positionSymbol, comment);
               } else if(prRecord.positionType == 1 && COPY_SELL) {
                  placeSellOrder(sic_trade, prRecord.positionSL, prRecord.positionTP, recVolDifference, positionSymbol, comment);
               }
            }
         } else if(prRecord.positionVolume < prCurrentVol) {//Vols size decreased
            if(ACCOUNT_MARGIN_MODE_RETAIL_NETTING == AccountInfoInteger(ACCOUNT_MARGIN_MODE)) {
               if(prRecord.positionType == 0 && COPY_BUY) {
                  placeSellOrder(sic_trade, prRecord.positionSL, prRecord.positionTP, recVolDifference, positionSymbol, comment);
               } else if(prRecord.positionType == 1 && COPY_SELL) {
                  placeBuyOrder(sic_trade, prRecord.positionSL, prRecord.positionTP, recVolDifference, positionSymbol, comment);
               }
            } else if(ACCOUNT_MARGIN_MODE_RETAIL_HEDGING == AccountInfoInteger(ACCOUNT_MARGIN_MODE)) {
               sic_trade.PositionClosePartial(recPosition.positionTicket,recVolDifference);
               //Save new provider volume so we can use to handle more than 1 partial close since we can't update comments with decreased volume...plus MT5 clears comments anyway on partial close so we need global var to check if ticket existed
               GlobalVariableSet("VOL-"+ IntegerToString(recPosition.positionTicket) +"-"+ IntegerToString(prRecord.positionTicket), prRecord.positionVolume); //Kinda redundent no since we set global var either way below for all existing deals ( for both netting and hedging)
            }
         }
         
         //Set record in global var so that we still have it even if comments get removed (helps fix issue of closing which no longer have comments to get provider ticket from)
         GlobalVariableSet("VOL-"+ IntegerToString(recPosition.positionTicket) +"-"+ IntegerToString(prRecord.positionTicket), prRecord.positionVolume);
      } else {
         double balance = AccountInfoDouble(ACCOUNT_BALANCE);
         double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         if(freeMargin <= (balance*MIN_AVALABLE_FUNDS_PERC)) {
            continue;
         }
         
         long now = ((long)TimeGMT()) * 1000;
         ulong positionTimeGMT = prRecord.positionOpenTime + (prTradeServerGMTOffset*1000);
         ulong millisecondsElapsed = now - positionTimeGMT;
         if(millisecondsElapsed > (EXCLUDE_OLDER_THAN_MINUTES*60*1000)) {
            continue;
         }
         if(prRecord.positionProfit > 0 && !COPY_IN_PROFIT) {
            continue;
         }
         double volume = prRecord.positionVolume;
         if(PROPORTIONAL_TO_BALANCE == LOT_SIZE) {
            double receiverAvailableFunds = balance;
            volume = volume * (receiverAvailableFunds/prAccountBalance);
         } else if(PROPORTIONAL_TO_FREE_MARGIN == LOT_SIZE) {
            double receiverAvailableFunds = freeMargin;
            volume = volume * (receiverAvailableFunds/prAccountBalance);
         }
         
         //Check leverage
         if(USE_LEVERAGE_FOR_LOT_CALCULATION) {
            double marginInit;
            double marginMaint;
            SymbolInfoMarginRate(positionSymbol,(prRecord.positionType == 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL),marginInit,marginMaint);
            double positionLeverage = 1/(NormalizeDouble(marginInit,3));
            long receiverLeverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
            
            //Default position leverage to 1 to avoid dividing by 0
            double prPositionLeverage = prRecord.positionLeverage;
            if(prPositionLeverage == 0) {
               prPositionLeverage = 1;
            }
            if(positionLeverage == 0) {
               positionLeverage = 1;
            }
            
            volume = volume * ((receiverLeverage*positionLeverage)/(prAccountLeverage*prPositionLeverage));
         }
         
         string comment = "[TKT="+ IntegerToString(prRecord.positionTicket) +",VOL="+DoubleToString(prRecord.positionVolume,2)+"]";
         
         if(prRecord.positionType == 0 && COPY_BUY) {
            placeBuyOrder(sic_trade, prRecord.positionSL, prRecord.positionTP, volume, positionSymbol, comment);
         } else if(prRecord.positionType == 1 && COPY_SELL) {
            placeSellOrder(sic_trade, prRecord.positionSL, prRecord.positionTP, volume, positionSymbol, comment);
         }
      }
   }
   
   return true;
}

bool closePositions() {
   sic_trade.SetExpertMagicNumber(prAccountNumber);
   sic_trade.SetMarginMode();
   sic_trade.SetDeviationInPoints(PRICE_DEVIATION);
   
   PositionData losersToClose[];
   int loserMatches = 0;
      
   int recPositionsSize = ArraySize(recPositions);
   for(int i=0; i<recPositionsSize; i++){
      PositionData recPosition = recPositions[i];
      
      sic_trade.SetTypeFillingBySymbol(recPosition.positionSymbol);
      
      //Close position no longer on provider side
      bool existsOnProvider = false;
      int prRecordsSize = ArraySize(prRecords);
      for(int i=0; i<prRecordsSize; i++){
         if(StringFind(recPosition.positionComment,"TKT="+ IntegerToString(prRecords[i].positionTicket)) != -1) { //-1 means no match
            existsOnProvider = true;
            break;
         } else if(GlobalVariableCheck("VOL-"+ IntegerToString(recPosition.positionTicket) +"-"+ IntegerToString(prRecords[i].positionTicket))) {
            existsOnProvider = true;
            break;
         }
      }
      if(!existsOnProvider) {
         if(recPosition.positionProfit < 0.00) {
            loserMatches++;
            ArrayResize(losersToClose,loserMatches);
            losersToClose[loserMatches-1] = recPosition;
            continue;
         }
         printHelper(LOG_INFO, StringFormat("Closing position %d as it no longer exists on provider side", recPosition.positionTicket));
         sic_trade.PositionClose(recPosition.positionTicket);
      }
   }
   
   if(loserMatches > 1 && ALERT_MULTIPLE_LOSERS_CLOSE) { //Alert and don't close positions
      string tickets = "";
      for(int i=0; i<loserMatches; i++) {
         tickets = tickets+"["+ IntegerToString(losersToClose[i].positionTicket) +"]";
      }
      string subject = "Closing of Multiple losers on receiver account "+ IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
      string body = StringFormat("Closing of multiple losing tickets %s looks suspicious. Please check and close them manually if still applicable", tickets);
      SendMail(subject,body);
   } else if(loserMatches > 0) {
      for(int i=0; i<loserMatches; i++) {
         printHelper(LOG_INFO, StringFormat("Closing position %d as it no longer exists on provider side", losersToClose[i].positionTicket));
         sic_trade.PositionClose(losersToClose[i].positionTicket);
      }
   }
   
   return true;
}

bool readPositions() {
   ulong startTime=GetTickCount64();
   int positionsFileHandle = INVALID_HANDLE;
   int timeWasted = 0;
   while(positionsFileHandle == INVALID_HANDLE) {
      positionsFileHandle = FileOpen(positionsFileName,FILE_READ|FILE_SHARE_READ|FILE_COMMON|FILE_TXT,',');
      if(positionsFileHandle == INVALID_HANDLE) {
         if(timeWasted >= FILE_MAXWAIT_MS) {
            printHelper(LOG_INFO, StringFormat("Failed to open file %s but will retry in %dms, error code %d", positionsFileName, PROCESSING_INTERVAL_MS, GetLastError()));
            return false;
         }
         timeWasted = timeWasted+FILE_RETRY_MS;
         Sleep(FILE_RETRY_MS);
      }
   }
   
   FileReadString(positionsFileHandle);//Discard the header line as we don't use it
   
   string accountDataLine = FileReadString(positionsFileHandle);
   string accountDataArray[10];
   StringSplit(accountDataLine,',',accountDataArray);
   prRecordCount = (int)StringToInteger(accountDataArray[0]); 
   prTimeLocal = (datetime)StringToInteger(accountDataArray[1]); 
   prTimeGMT = (datetime)StringToInteger(accountDataArray[2]); 
   prAccountNumber = StringToInteger(accountDataArray[3]); 
   prAccountBalance = StringToDouble(accountDataArray[4]); 
   prAccountEquity = StringToDouble(accountDataArray[5]); 
   prAccountCurrency = accountDataArray[6];
   prAccountLeverage = (int)StringToInteger(accountDataArray[7]);
   prMarginMode = (int)StringToInteger(accountDataArray[8]);
   prTradeServerGMTOffset = StringToInteger(accountDataArray[9]);
   
   FileReadString(positionsFileHandle);//Discard the header line as we don't use it
   
   ArrayResize(prRecords,prRecordCount);
   
   int i = 0;
   while(!FileIsEnding(positionsFileHandle)){
      string line = FileReadString(positionsFileHandle);
      //TODO: split string and add struct into array
      string tmpArray[12];
      StringSplit(line, ',', tmpArray);
      
      PositionData prData;
      prData.seq = (int)StringToInteger(tmpArray[0]);
      prData.positionMagic = 0;
      prData.positionTicket = StringToInteger(tmpArray[1]);
      prData.positionOpenTime = StringToInteger(tmpArray[2]);
      prData.positionType = (int)StringToInteger(tmpArray[3]);
      prData.positionVolume = StringToDouble(tmpArray[4]);
      prData.positionPriceOpen = StringToDouble(tmpArray[5]);
      prData.positionSL = StringToDouble(tmpArray[6]);
      prData.positionTP = StringToDouble(tmpArray[7]);
      prData.positionProfit = StringToDouble(tmpArray[8]);
      prData.positionSymbol = tmpArray[9];
      prData.positionComment = tmpArray[10];
      prData.positionLeverage = (int)StringToInteger(tmpArray[11]);
      
      prRecords[i] = prData;
      
      i++;
   }
   
   FileClose(positionsFileHandle);
   
   ulong endTime=GetTickCount64();
   printHelper(LOG_INFO, StringFormat("Reading from file took %d milliseconds", endTime-startTime));
   
   return true;
}

bool writePositions() {
   ulong startTime=GetTickCount64();
   uint posTotal=PositionsTotal();
   ulong positionTicket;
   ulong accountNumber =AccountInfoInteger(ACCOUNT_LOGIN);
   string accountCurrency =AccountInfoString(ACCOUNT_CURRENCY);
   double accountBalance =AccountInfoDouble(ACCOUNT_BALANCE);
   double accountEquity =AccountInfoDouble(ACCOUNT_EQUITY);
   int accountLeverage = (int)AccountInfoInteger(ACCOUNT_LEVERAGE);
   int margingMode = (int)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   string nTimeLocal = TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS);
   string nTimeGMT = TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS);
   long tradeServerGMTOffset = TimeGMT() - TimeTradeServer();
   
   int positionsFileHandle = INVALID_HANDLE;
   int timeWasted = 0;
   while(positionsFileHandle == INVALID_HANDLE) {
      if(REMOTE_FTP_PUBLISH) { //sendFTP expects file in current termial folder so can't put it in common folder'
         positionsFileHandle = FileOpen(positionsFileName,FILE_WRITE|FILE_TXT,',');
      } else {
         positionsFileHandle = FileOpen(positionsFileName,FILE_WRITE|FILE_COMMON|FILE_TXT,',');
      }
      if(positionsFileHandle == INVALID_HANDLE) {
         if(timeWasted >= FILE_MAXWAIT_MS) {
            printHelper(LOG_INFO, StringFormat("Failed to open file %s but will retry in %dms, error code %d", positionsFileName, PROCESSING_INTERVAL_MS, GetLastError()));
            return false;
         }
         timeWasted = timeWasted+FILE_RETRY_MS;
         Sleep(FILE_RETRY_MS);
      }
   }

   FileWrite(positionsFileHandle, "RecordCount", "TimeLocal", "TimeGMT", "AccountNumber", "Balance", "Equity", "Currency", "Leverage", "MarginMode","TradeServer GMT Offset");
   FileWrite(positionsFileHandle, posTotal ,nTimeLocal, nTimeGMT, accountNumber, accountBalance, accountEquity, accountCurrency, accountLeverage, margingMode, tradeServerGMTOffset);
   FileWrite(positionsFileHandle,"Seq","PositionTicket","PositionOpenTime",
             "PositionType", "PositionVolume", "PositionPriceOpen","PositionSL","PositionTP",
             "PositionProfit", "PositionSymbol", "PositionComment", "PositionLeverage");

   for(uint i=0; i<posTotal; i++) {
      //--- return order ticket by its position in the list
      positionTicket=PositionGetTicket(i);
      if(positionTicket>0) {//Meaning the position exists,
         //--- Loading Position Information
         ulong positionOpenTime = PositionGetInteger(POSITION_TIME_MSC);
         int positionType= (int)PositionGetInteger(POSITION_TYPE);    // type of the position
         double positionVolume=PositionGetDouble(POSITION_VOLUME);
         double positionPriceOpen=PositionGetDouble(POSITION_PRICE_OPEN);
         double positionSL = PositionGetDouble(POSITION_SL);
         double positionTP=PositionGetDouble(POSITION_TP);
         double positionProfit=PositionGetDouble(POSITION_PROFIT);
         string positionSymbol = PositionGetString(POSITION_SYMBOL);
         string positionComment = PositionGetString(POSITION_COMMENT);
         
         double marginInit;
         double marginMaint;
         SymbolInfoMarginRate(positionSymbol,(positionType == 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL),marginInit,marginMaint);
         double positionLeverage = 1/(NormalizeDouble(marginInit,3));
         
         FileWrite(positionsFileHandle, i, positionTicket,positionOpenTime,positionType, positionVolume, positionPriceOpen,positionSL,positionTP, positionProfit, positionSymbol, positionComment, positionLeverage);
      }
   }
   
   FileClose(positionsFileHandle);
   
   printHelper(LOG_INFO, "File "+positionsFileName+" updated, there were "+IntegerToString(posTotal)+" positions in the system.");
   ulong endTime=GetTickCount64();
   printHelper(LOG_INFO, StringFormat("Writing to file took %d milliseconds", endTime-startTime));

   return true;
}

void downloadFile() {
   string credentials = REMOTE_USERNAME+":"+REMOTE_PASSWORD;
   string key="";
   uchar srcArray[],dstArray[],keyArray[];
   StringToCharArray(key,keyArray);
   StringToCharArray(credentials,srcArray);
   CryptEncode(CRYPT_BASE64,srcArray,keyArray,dstArray);
   
   string cookie=NULL;
   string headers = "Authorization: Basic "+CharArrayToString(dstArray);
   char   data[],result[];
   
   ResetLastError();
   
   printHelper(LOG_DEBUG, StringFormat("HTTP Headers before: %s",headers));
   int res=WebRequest("GET",REMOTE_FILE_URL,headers,500,data,result,headers);
   if(res == -1) {
      printHelper(LOG_WARN, StringFormat("Error in download WebRequest. Error code %s",GetLastError()));
      //--- Perhaps the URL is not listed, display a message about the necessity to add the address
      printHelper(LOG_WARN, StringFormat("Add the address %s to the list of allowed URLs on tab 'Expert Advisors'",REMOTE_FILE_URL));
   } else {
      if(res == 200) {
         //--- Successful download
         printHelper(LOG_INFO, StringFormat("Remote file downloaded, File size is %d bytes",ArraySize(result)));
         if(ArraySize(result) > 0) {
            int fileHandle = FileOpen(positionsFileName,FILE_WRITE|FILE_COMMON|FILE_BIN); 
            if(fileHandle != INVALID_HANDLE) { 
               //--- Saving the contents of the result[] array to a file 
               FileWriteArray(fileHandle,result,0,ArraySize(result)); 
               
               FileClose(fileHandle); 
            } 
         } else {
            printHelper(LOG_WARN, StringFormat("Not processing file as size is %d",ArraySize(result)));
         }
      } else{
         printHelper(LOG_WARN, StringFormat("Remote file '%s' download failed, error code %d",REMOTE_FILE_URL,res));
         printHelper(LOG_DEBUG, StringFormat("HTTP Headers after: %s",headers));
      }
   }
}

void processHeartbeat() {
   ulong now =GetTickCount64();
   if((now-lastHeartbeatTime) < (HEARTBEAT_INTERVAL_MINUTES*60*1000)) {
      return;
   }
   
   string cookie=NULL,headers;
   char   data[],result[];
   
   ResetLastError();
   
   int res=WebRequest("POST",HEARTBEAT_URL,cookie,NULL,500,data,0,result,headers);
   if(res == -1) {
      printHelper(LOG_WARN, StringFormat("Error in heartbeat WebRequest. Error code %s",GetLastError()));
      //--- Perhaps the URL is not listed, display a message about the necessity to add the address
      printHelper(LOG_WARN, StringFormat("Add the address %s to the list of allowed URLs on tab 'Expert Advisors'",HEARTBEAT_URL));
   } else {
      if(res == 200) {
         //--- Successful transmission
         printHelper(LOG_INFO, StringFormat("Heartbeat sent, Server Result: %s", CharArrayToString(result)));
      } else{
         printHelper(LOG_WARN, StringFormat("Heartbeat transmission '%s' failed, error code %d",HEARTBEAT_URL,res));
      }
   }
   
   lastHeartbeatTime = GetTickCount64();
}

