//+------------------------------------------------------------------+
//|                                            TradeBreakOut_MTF.mq4 |
//|                             Copyright © 2013-2025, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013-2025, www.EarnForex.com"
#property link      "https://www.earnforex.com/indicators/TradeBreakOut/"
#property version   "1.02"
#property strict

#property description "Red line crossing 0 from above is a support breakout signal."
#property description "Green line crossing 0 from below is a resistance breakout signal."
#property description "Multi-timeframe operation is supported."

#property indicator_separate_window
#property indicator_buffers 2
#property indicator_level1 0
#property indicator_levelwidth 1
#property indicator_levelstyle STYLE_DOT
#property indicator_levelcolor clrDarkGray
#property indicator_type1  DRAW_LINE
#property indicator_color1 clrGreen
#property indicator_label1 "Resistance Breakout"
#property indicator_type2  DRAW_LINE
#property indicator_color2 clrRed
#property indicator_label2 "Support Breakout"

enum ENUM_PRICE
{
    PriceClose, // Close
    PriceHighLow, // High/Low
};

enum ENUM_CANDLE_TO_CHECK
{
    CURRENT_CANDLE, // Current Candle
    CLOSED_CANDLE   // Previous Candle
};

enum ENUM_TRADE_SIGNAL
{
    SIGNAL_BUY = 1,     // Buy
    SIGNAL_SELL = -1,   // Sell
    SIGNAL_NEUTRAL = 0, // Neutral
};

input ENUM_TIMEFRAMES TimeFrame = PERIOD_CURRENT; // Timeframe
input int L = 50; // Period
input ENUM_PRICE PriceType = PriceHighLow; // Price
input bool EnableNativeAlerts  = false;
input bool EnableEmailAlerts   = false;
input bool EnablePushAlerts    = false;
input bool EnableSoundAlerts   = false;
input string SoundFile = "alert.wav";
input ENUM_CANDLE_TO_CHECK TriggerCandle = CURRENT_CANDLE; // Trigger Candle (Only for Close Price Mode)
input bool EnableDrawArrows = true;                        // Draw Signal Arrows
input int ArrowBuy = 241;                                  // Buy Arrow Code
input int ArrowSell = 242;                                 // Sell Arrow Code
input int ArrowSize = 3;                                   // Arrow Size (1-5)
input color ArrowBuyColor = clrGreen;                      // Buy Arrow Color
input color ArrowSellColor = clrRed;                       // Sell Arrow Color
input string IndicatorName = "TBO";                        // Indicator Short Name

// Buffers:
double TBR_R[], TBR_S[];

// Alert tracking:
datetime LastAlertTimeBuy = D'01.01.1970';
datetime LastAlertTimeSell = D'01.01.1970';
ENUM_TRADE_SIGNAL LastSignal = SIGNAL_NEUTRAL;

// MTF-related:
ENUM_TIMEFRAMES MTF_Period;
string MTF_Suffix;
bool MTF_Mode;
int TF_Multiplier;

int Shift; // A global-scope variable for TriggerCandle.

void OnInit()
{
    SetIndexBuffer(0, TBR_R);
    SetIndexBuffer(1, TBR_S);

    if (PeriodSeconds(TimeFrame) <= PeriodSeconds()) // Same or lower timeframe given.
    {
        MTF_Period = (ENUM_TIMEFRAMES)Period();
        MTF_Mode = false;
        TF_Multiplier = 1;
        MTF_Suffix = "";
    }
    else
    {
        MTF_Period = TimeFrame;
        MTF_Mode = true;
        TF_Multiplier = PeriodSeconds(TimeFrame) / PeriodSeconds(); // To multiply L.
        MTF_Suffix = GetTimeFrameString(MTF_Period);
    }

    // In MTF, L bars of the upper timeframe.
    SetIndexDrawBegin(0, L * TF_Multiplier);
    SetIndexDrawBegin(1, L * TF_Multiplier);

    SetIndexEmptyValue(0, EMPTY_VALUE);
    SetIndexEmptyValue(1, EMPTY_VALUE);

    string short_name = IndicatorName + " (" + IntegerToString(L);
    if (MTF_Mode) short_name += ", " + MTF_Suffix;
    short_name += ")";
    IndicatorShortName(short_name);
    IndicatorDigits(5); // High precision irrespective of the number of decimal places in quotes.

    if (PriceType == PriceHighLow) Shift = 0; // Always latest bar for High/Low.
    else Shift = TriggerCandle;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime& time[],
                const double& open[],
                const double& high[],
                const double& low[],
                const double& close[],
                const long& tick_volume[],
                const long& volume[],
                const int& spread[]
)
{    
    int mtf_bars = iBars(Symbol(), MTF_Period);

    if (mtf_bars <= L) return 0;

    bool IsNewCandle = CheckIfNewCandle();

    int limit;
    if (prev_calculated == 0)
    {
        limit = rates_total - 1;
    }
    else
    {
        limit = rates_total - prev_calculated + TF_Multiplier; // Make sure the entire upper timeframe bar is recalculated.
        if (limit >= rates_total) limit = rates_total - 1;
    }
    
    for (int i = limit; i >= 0; i--)
    {
        int mtf_shift = i;
        if (MTF_Mode)
        {
            // Get the corresponding MTF bar index.
            mtf_shift = iBarShift(Symbol(), MTF_Period, Time[i]);

            // Check if we have enough MTF bars to calculate.
            if (mtf_shift < 0 || mtf_shift + L >= mtf_bars)
            {
                TBR_R[i] = EMPTY_VALUE;
                TBR_S[i] = EMPTY_VALUE;
                continue;
            }
        }

        // Calculate values using data from the given timeframe.
        if (PriceType == PriceClose)
        {
            double max_close = 0;
            double min_close = DBL_MAX;

            // Find max and min in the L bars before current bar.
            for (int j = 1; j <= L; j++)
            {
                double close_val = iClose(Symbol(), MTF_Period, mtf_shift + j);
                if (close_val > max_close) max_close = close_val;
                if (close_val < min_close) min_close = close_val;
            }

            double current_close = iClose(Symbol(), MTF_Period, mtf_shift);
            
            if (max_close != 0)
            {
                TBR_R[i] = (current_close - max_close) / max_close;
            }
            else
            {
                TBR_R[i] = EMPTY_VALUE;
            }

            if (min_close != 0 && min_close != DBL_MAX)
            {
                TBR_S[i] = (current_close - min_close) / min_close;
            }
            else
            {
                TBR_S[i] = EMPTY_VALUE;
            }
        }
        else if (PriceType == PriceHighLow)
        {
            double max_high = 0;
            double min_low = DBL_MAX;

            // Find max high and min low in the L bars before current bar.
            for (int j = 1; j <= L; j++)
            {
                double high_val = iHigh(Symbol(), MTF_Period, mtf_shift + j);
                double low_val = iLow(Symbol(), MTF_Period, mtf_shift + j);
                if (high_val > max_high) max_high = high_val;
                if (low_val < min_low) min_low = low_val;
            }

            double current_high = iHigh(Symbol(), MTF_Period, mtf_shift);
            double current_low = iLow(Symbol(), MTF_Period, mtf_shift);
            
            if (max_high != 0)
            {
                TBR_R[i] = (current_high - max_high) / max_high;
            }
            else
            {
                TBR_R[i] = EMPTY_VALUE;
            }    
            if (min_low != 0 && min_low != DBL_MAX)
            {
                TBR_S[i] = (current_low - min_low) / min_low;
            }
            else
            {
                TBR_S[i] = EMPTY_VALUE;
            }
        }
    }

    if ((IsNewCandle) || (prev_calculated == 0))
    {
        if (MTF_Mode && limit != rates_total - 1) limit -= TF_Multiplier; // Avoid adding a new arrow for the MTF bar which already has one.
        if (EnableDrawArrows) DrawArrows(limit);
    }

    if (EnableDrawArrows) DrawArrow(0);

    if (EnableNativeAlerts || EnableEmailAlerts || EnablePushAlerts || EnableSoundAlerts) CheckAlerts();

    return rates_total;
}

void CheckAlerts()
{
    if ((PriceType == PriceClose && ((Shift > 0 && iTime(Symbol(), MTF_Period, 0) > MathMax(LastAlertTimeBuy, LastAlertTimeSell)) || Shift == 0)) || // Classic check for Close price alerts.
         PriceType == PriceHighLow) // High/Low price - check only for signal repetition further below.
    {
        int curr_index = Shift;
        // Find curr index for MTF.
        if (MTF_Mode && Shift == 1)
        {
            for (; curr_index < Bars && Time[curr_index] >= iTime(Symbol(), MTF_Period, 0); curr_index++)
            {
            }
        }
        // Find prev index for MTF.
        int prev_index = 1 + Shift;
        if (MTF_Mode && TriggerCandle == 0)
        {
            for (; prev_index < Bars && Time[prev_index] >= iTime(Symbol(), MTF_Period, 0); prev_index++)
            {
            }
        }
        bool NoBuySignal = false, NoSellSignal = false;
        // Buy signal.
        if ((TBR_R[curr_index] > 0) && (TBR_R[curr_index] != EMPTY_VALUE) && 
            (TBR_R[prev_index] <= 0) && (TBR_R[prev_index] != EMPTY_VALUE))
        {
            NoBuySignal = false;
            if ((PriceType == PriceClose && LastSignal != SIGNAL_BUY) || (PriceType == PriceHighLow && iTime(Symbol(), MTF_Period, 0) > LastAlertTimeBuy))
            {
                IssueAlertsBuy(iTime(Symbol(), MTF_Period, 0));
            }
        }
        else NoBuySignal = true;
        // Sell signal.
        if ((TBR_S[curr_index] < 0) && (TBR_S[curr_index] != EMPTY_VALUE) && 
            (TBR_S[prev_index] >= 0) && (TBR_S[prev_index] != EMPTY_VALUE))
        {
            NoSellSignal = false;
            if ((PriceType == PriceClose && LastSignal != SIGNAL_SELL) || (PriceType == PriceHighLow && iTime(Symbol(), MTF_Period, 0) > LastAlertTimeSell))
            {
                IssueAlertsSell(iTime(Symbol(), MTF_Period, 0));
            }
        }
        else NoSellSignal = true;
        if (NoBuySignal && NoSellSignal) LastSignal = SIGNAL_NEUTRAL; 
    }
}

void IssueAlertsBuy(datetime time)
{
    string Text;
    Text = "TBO: " + Symbol();
    if (MTF_Mode) Text += " - " + MTF_Suffix; 
    Text += " on " + GetTimeFrameString((ENUM_TIMEFRAMES)Period()) + " - Crossed 0 from below.";
    if (EnableNativeAlerts) Alert(Text);
    if (EnableEmailAlerts) SendMail("TBO Alert", Text);
    if (EnablePushAlerts) SendNotification(Text);
    if (EnableSoundAlerts) PlaySound(SoundFile);
    LastAlertTimeBuy = time;
    LastSignal = SIGNAL_BUY;
}

void IssueAlertsSell(datetime time)
{
    string Text;
    Text = "TBO: " + Symbol();
    if (MTF_Mode) Text += " - " + MTF_Suffix;
    Text += " on " + GetTimeFrameString((ENUM_TIMEFRAMES)Period()) + " - Crossed 0 from above.";
    if (EnableNativeAlerts) Alert(Text);
    if (EnableEmailAlerts) SendMail("TBO Alert", Text);
    if (EnablePushAlerts) SendNotification(Text);
    if (EnableSoundAlerts) PlaySound(SoundFile);
    LastAlertTimeSell = time;
    LastSignal = SIGNAL_SELL;
}

void OnDeinit(const int reason)
{
    CleanChart();
}

void CleanChart()
{
    ObjectsDeleteAll(ChartID(), IndicatorName);
}

// Check if it is a trade signal.
void IsSignal(int i, bool &signal_buy, bool &signal_sell)
{
    signal_buy = false;
    signal_sell = false;
    int j = i + Shift;

    if (j + 1 >= Bars) return;

    int curr_index = j;
    if (MTF_Mode && Shift == 1 && i == 0)
    {
        datetime mtf_time = iTime(Symbol(), MTF_Period, 0);
        for (; curr_index < Bars - 1 && Time[curr_index] >= mtf_time; curr_index++)
        {
        }
    }
    int prev_index = curr_index + 1;
    if (MTF_Mode)
    {
        int mtf_shift = iBarShift(Symbol(), MTF_Period, Time[curr_index]);
        datetime mtf_time = iTime(Symbol(), MTF_Period, mtf_shift);
        for (; prev_index < Bars - 1 && Time[prev_index] >= mtf_time; prev_index++)
        {
        }
    }

    if (TBR_R[curr_index] > 0 && TBR_R[curr_index] != EMPTY_VALUE && 
        TBR_R[prev_index] <= 0 && TBR_R[prev_index] != EMPTY_VALUE) signal_buy = true;
    if (TBR_S[curr_index] < 0 && TBR_S[curr_index] != EMPTY_VALUE && 
        TBR_S[prev_index] >= 0 && TBR_S[prev_index] != EMPTY_VALUE) signal_sell = true;
}

datetime NewCandleTime = TimeCurrent();
bool CheckIfNewCandle()
{
    if (NewCandleTime == iTime(Symbol(), Period(), 0)) return false;
    else
    {
        NewCandleTime = iTime(Symbol(), Period(), 0);
        return true;
    }
}

void DrawArrows(int limit)
{
    for (int i = limit - 1; i >= 1; i--)
    {
        DrawArrow(i);
    }
}

void DrawArrow(int i)
{
    if (MTF_Mode)
    {
        if (Shift == 1 && i < Bars - 1)
        {
            if (iBarShift(Symbol(), MTF_Period, Time[i]) == iBarShift(Symbol(), MTF_Period, Time[i + 1])) return; // If i isn't the first bar of the higher TF bar, skip.
        }
        else if (Shift == 0 && i > 0)
        {
            if (iBarShift(Symbol(), MTF_Period, Time[i]) == iBarShift(Symbol(), MTF_Period, Time[i - 1])) return; // If i isn't the last bar of the higher TF bar, skip.
        }
    }
    if (i == 0) RemoveArrowCurr();

    bool signal_buy = false, signal_sell = false;
    IsSignal(i, signal_buy, signal_sell);
    ENUM_TRADE_SIGNAL Signal = SIGNAL_NEUTRAL;
    if (PriceType == PriceClose)
    {
        if (signal_buy) Signal = SIGNAL_BUY;
        else if (signal_sell) Signal = SIGNAL_SELL;
        if (Signal == SIGNAL_NEUTRAL) return;
        DrawArrowObject(Signal, i);
    }
    else // High/Low
    {
        if (signal_buy) DrawArrowObject(SIGNAL_BUY, i);
        if (signal_sell) DrawArrowObject(SIGNAL_SELL, i);
    }
}

void DrawArrowObject(ENUM_TRADE_SIGNAL Signal, int i)
{
    datetime ArrowDate = iTime(Symbol(), 0, i);
    string ArrowName = IndicatorName + "-ARWS-";
    double ArrowPrice = 0;
    int ArrowType = 0;
    color ArrowColor = 0;
    int ArrowAnchor = 0;
    int ArrowCode = 0;
    string ArrowDesc = "";
    if (Signal == SIGNAL_BUY)
    {
        ArrowPrice = Low[i];
        ArrowType = ArrowBuy;
        ArrowColor = ArrowBuyColor;
        ArrowAnchor = ANCHOR_TOP;
        ArrowDesc = "BUY";
        ArrowName += "B";
    }
    else if (Signal == SIGNAL_SELL)
    {
        ArrowPrice = High[i];
        ArrowType = ArrowSell;
        ArrowColor = ArrowSellColor;
        ArrowAnchor = ANCHOR_BOTTOM;
        ArrowDesc = "SELL";
        ArrowName += "S";
    }
    ArrowName += IntegerToString(ArrowDate);
    ObjectCreate(ChartID(), ArrowName, OBJ_ARROW, 0, ArrowDate, ArrowPrice);
    ObjectSetInteger(ChartID(), ArrowName, OBJPROP_COLOR, ArrowColor);
    ObjectSetInteger(ChartID(), ArrowName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(ChartID(), ArrowName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(ChartID(), ArrowName, OBJPROP_ANCHOR, ArrowAnchor);
    ObjectSetInteger(ChartID(), ArrowName, OBJPROP_ARROWCODE, ArrowType);
    ObjectSetInteger(ChartID(), ArrowName, OBJPROP_WIDTH, ArrowSize);
    ObjectSetInteger(ChartID(), ArrowName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(ChartID(), ArrowName, OBJPROP_BGCOLOR, ArrowColor);
    ObjectSetString(ChartID(), ArrowName, OBJPROP_TOOLTIP, ArrowDesc);
}

void RemoveArrowCurr()
{
    // Update all bars that belong to this MTF bar. Works in non-MTF mode as well.
    datetime time_mtf = iTime(Symbol(), MTF_Period, 0);
    for (int i = 0; i < Bars; i++)
    {
        datetime time = Time[i];
        if (time >= time_mtf)
        {
            datetime ArrowDate = time;
            string ArrowName = IndicatorName + "-ARWS-B" + IntegerToString(ArrowDate);
            ObjectDelete(ChartID(), ArrowName);
            ArrowName = IndicatorName + "-ARWS-S" + IntegerToString(ArrowDate);
            ObjectDelete(ChartID(), ArrowName);
        }
        else break; // No need to check older bars.
    }
}

string GetTimeFrameString(ENUM_TIMEFRAMES period)
{
   return StringSubstr(EnumToString((ENUM_TIMEFRAMES)period), 7);
}
//+------------------------------------------------------------------+