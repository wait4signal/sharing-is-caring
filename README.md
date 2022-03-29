# **Sharing-Is-Caring** [MT5]    

## **Features**
- Local & Remote copy
- One tool can act as provider or receiver of trades
- Co-exist with other positions opened manually or from other expert advisors
- Can be stopped and restarted at any time without any issues such as deals getting closed mysteriously
- Copy same lot or adjust according to your balance and leverage
- Partial close/open
- Manage max funds to use
- One provider can copy to unlimited number of receivers
- One receiver can copy from unlimited number of providers
- Monitoring using heartbeat checks

## **About**
This is a MetaTrader 5 EA.   
The tool is designed for simplicity and speed and I use it daily in my trading.   
In my use-case the copier helps with the psychology of trading large accounts and keeping emotions under control. I have a small account which I use for trading. Then I have other accounts which are comparatively large, about 10x but can even be 100x.   
These accounts simply copy the trades from the small account using the copier and sizing trades proportionally.   
This way I can just keep my trading account small like $5k but have the other accounts at like $100k and trade without panic as the large accounts are out of sight and I just focus on the small one which does not induce as much stress.

### **Notes**:
Account types need to match i.e hedging providers to be used with hedging receivers and vice versa.
Ideally, Provider and Receiver accounts should use same currency denomination for accurate lot calculation using balances.
Try using the same broker to avoid slippage and issues with unmatching speed.

## **Code and License**
The source code for this EA is released under GPL v3 and is available at https://github.com/wait4signal/sharing-is-caring/blob/main/Sharing-Is-Caring.mq5

# **Getting started**

## **Installation**
The EA can be installed using the binaries from the MT5 marketplace at the following link:   
(https://www.mql5.com/en/market/product/68484)   

Altenatively you can compile the source code locally using the MT5 editor.   
You only need to attach the EA onto one of the charts running on the MT5 terminal, it will then process all the transactions occurring on the entire account.

## **Configuration**
Very easy to get started, just select the preferred COPY_MODE and depending on the mode the following may apply.
### **Provider**:
>If “PROVIDER” is selected then the rest of the settings are optional and depending on features used.

### **Receiver**:
>If “RECEIVER” then you also need to specify the “PROVIDER_ACCOUNT” which is the trading account whose trades will be copied. The rest of the settings are optional depending on features used.

### **Local vs Remote copy**:
Position data is written by the provider to a csv file. The receiver/s then reads from this file.
This is the preferred method as it is fastest, it is used when the provider and receivers are running on the same machine.   
However if there are receivers running on a remote machine then the provider should be set to also write the data to a remote file location. The remote receivers would then also be set to read from this remote location.   
By default, position data is saved locally onto a file named **/Terminal\Common\Files\Sharing-Is-Caring\[providerAccount]-positions.csv*   
Trades from a remote location also get written to this file prior to use.   
**To upload/share trades via ftp, you need to configure ftp server,path and credentials in the FTP tab under options*   
**Conversely, remote trades are downloaded via http using the "Remote Copy" EA parameters*

## **Monitoring**
The copier can be set to send health checks to a monitoring server so that alerts can be sent out if no heartbeat pings are received within a set timeframe.   
We recommend the https://healthchecks.io/ platform for this as it is open-source and supports a large number of alerting mechanisms such as email,telegram,phone call etc. Plus it offers up to 20 free monitoring licenses.   
Note that your alert interval needs to be longer than the heartbeat interval e.g if heartbeat is set to 5 minutes then on the monitoring server you can set alerting to something like 7 minutes so that you get notified if the terminal has not sent a ping in 7 minutes.   
**Configure the email tab under options for this to work*

## **Terminal global variables**
The following global variables can be set at terminal level to control certain program behaviour:

| Variable    `[defaults in brackets]`    | Description `[valid values in brackets]`                                                                                               |
|-----------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------|
| LOG_LEVEL   `[0]`                       | Sets log level: `[0 \| 1 \| 2 \| 3 \| 4]` where LOG_NONE  = 0; LOG_ERROR = 1; LOG_WARN  = 2; LOG_INFO  = 3; LOG_DEBUG = 4              |

## **Settings**
See the following link for detailed explanation of the available settings:
(https://github.com/wait4signal/sharing-is-caring/blob/main/Sharing-Is-Caring-settings.md)

