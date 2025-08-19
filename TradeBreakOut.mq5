//+------------------------------------------------------------------+
//|                                                TradeBreakOut.mq5 |
//|                             Copyright © 2013-2025, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013-2025, www.EarnForex.com"
#property link      "https://www.earnforex.com/indicators/TradeBreakOut/"
#property version   "1.02"

#property description "Red line crossing 0 from above is a support breakout signal."
#property description "Green line crossing 0 from below is a resistance breakout signal."
#property description "Multi-timeframe operation is supported."

#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots 2
#property indicator_level1 0
#property indicator_levelwidth 1
#property indicator_levelstyle STYLE_DOT
#property indicator_levelcolor clrDarkGray
#property indicator_color1 clrGreen
#property indicator_type1 DRAW_LINE
#property indicator_label1 "Resistance Breakout"
#property indicator_color2 clrRed
#property indicator_type2 DRAW_LINE
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
double TBR_R[], TBR_S[]; // Main indicator buffers.
double UpperTFShift[]; // An auxiliary array to store bar shift values from the higher timeframe mapped to the current timeframe.
double UpperTFTime[]; // An auxiliary array to store bar datetime values from the higher timeframe mapped to the current timeframe.

// Alert tracking:
datetime LastAlertTimeBuy = D'01.01.1970';
datetime LastAlertTimeSell = D'01.01.1970';
ENUM_TRADE_SIGNAL LastSignal = SIGNAL_NEUTRAL;

// MTF-related:
ENUM_TIMEFRAMES MTF_Period;
string MTF_Suffix;
bool MTF_Mode;
int TF_Multiplier;
bool JustRefreshed; // MTF flag used to mark if an attempt to refresh the chart was made. It is done when higher TF chart returns zero bars.

int Shift; // A global-scope variable for TriggerCandle.

void OnInit()
{
    if (TimeFrame <= Period()) // Same or lower timeframe given.
    {
        MTF_Period = Period();
        MTF_Mode = false;
        TF_Multiplier = 1;
        MTF_Suffix = "";
    }
    else // Higher timeframe given.
    {
        MTF_Period = TimeFrame;
        MTF_Mode = true;
        TF_Multiplier = PeriodSeconds(TimeFrame) / PeriodSeconds(); // To multiply L.
        MTF_Suffix = GetTimeFrameString(MTF_Period);
    }

    SetIndexBuffer(0, TBR_R, INDICATOR_DATA);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, L * TF_Multiplier);

    SetIndexBuffer(1, TBR_S, INDICATOR_DATA);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, L * TF_Multiplier);

    string short_name = IndicatorName + " (" + IntegerToString(L);
    if (MTF_Mode)
    {
        SetIndexBuffer(2, UpperTFShift, INDICATOR_CALCULATIONS);
        SetIndexBuffer(3, UpperTFTime, INDICATOR_CALCULATIONS);
        short_name += ", " + MTF_Suffix;
    }
    short_name += ")";
    IndicatorSetString(INDICATOR_SHORTNAME, short_name);
    IndicatorSetInteger(INDICATOR_DIGITS, 5); // High precision irrespective of the number of decimal places in quotes.

    if (PriceType == PriceHighLow) Shift = 0; // Always latest bar for High/Low.
    else Shift = TriggerCandle;

    JustRefreshed = false;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    int mtf_bars = iBars(Symbol(), MTF_Period); // Works for non-MTF as well.

    if (mtf_bars == 0)
    {
        if (JustRefreshed) return rates_total; // Avoid infinite refreshing on the same data in MTF mode.
        JustRefreshed = true;
        ChartSetSymbolPeriod(0, NULL, 0); // Forces refresh.
        return 0; // Higher TF data not loaded yet.
    }

    if (mtf_bars <= L) return 0;

    bool IsNewCandle = CheckIfNewCandle();

    int start;
    if (prev_calculated == 0)
    {
        start = 0;
    }
    else
    {
        start = prev_calculated - TF_Multiplier; // Make sure the entire upper timeframe bar is recalculated.
        if (start < 0) start = 0;
    }

    for (int i = start; i < rates_total; i++)
    {
        int mtf_shift = rates_total - 1 - i; // Non-MTF by default.        
        if (MTF_Mode)
        {
            mtf_shift = iBarShiftCustom(Symbol(), MTF_Period, time[i]); // Find the MTF one.
            // Check if we have enough MTF bars to calculate.
            if (mtf_shift < 0 || mtf_shift + L >= mtf_bars)
            {
                TBR_R[i] = EMPTY_VALUE;
                TBR_S[i] = EMPTY_VALUE;
                continue;
            }
            UpperTFShift[i] = mtf_bars - 1 - mtf_shift; // Now it can be used everywhere else.
            UpperTFTime[i] = (double)iTime(Symbol(), MTF_Period, mtf_shift); // Now it can be used everywhere else.
        }

        // Calculate values using data from the given timeframe.
        if (PriceType == PriceClose)
        {
            double close_array[];
            ArrayResize(close_array, L);

            // Copy MTF (or current) close prices.
            if (CopyClose(Symbol(), MTF_Period, mtf_shift + 1, L, close_array) != L)
            {
                TBR_R[i] = EMPTY_VALUE;
                TBR_S[i] = EMPTY_VALUE;
                continue;
            }

            int max_idx = ArrayMaximum(close_array);
            int min_idx = ArrayMinimum(close_array);

            double current_close = iClose(Symbol(), MTF_Period, mtf_shift);

            if (close_array[max_idx] != 0)
            {
                TBR_R[i] = (current_close - close_array[max_idx]) / close_array[max_idx];
            }
            else
            {
                TBR_R[i] = EMPTY_VALUE;
            }

            if (close_array[min_idx] != 0)
            {
                TBR_S[i] = (current_close - close_array[min_idx]) / close_array[min_idx];
            }
            else
            {
                TBR_S[i] = EMPTY_VALUE;
            }
        }
        else if (PriceType == PriceHighLow)
        {
            double high_array[], low_array[];
            ArrayResize(high_array, L);
            ArrayResize(low_array, L);

            // Copy MTF (or current) high and low prices.
            if (CopyHigh(Symbol(), MTF_Period, mtf_shift + 1, L, high_array) != L ||
                CopyLow(Symbol(), MTF_Period, mtf_shift + 1, L, low_array) != L)
            {
                TBR_R[i] = EMPTY_VALUE;
                TBR_S[i] = EMPTY_VALUE;
                continue;
            }

            int max_idx = ArrayMaximum(high_array);
            int min_idx = ArrayMinimum(low_array);

            double current_high = iHigh(Symbol(), MTF_Period, mtf_shift);
            double current_low = iLow(Symbol(), MTF_Period, mtf_shift);

            if (high_array[max_idx] != 0)
            {
                TBR_R[i] = (current_high - high_array[max_idx]) / high_array[max_idx];
            }
            else
            {
                TBR_R[i] = EMPTY_VALUE;
            }

            if (low_array[min_idx] != 0)
            {
                TBR_S[i] = (current_low - low_array[min_idx]) / low_array[min_idx];
            }
            else
            {
                TBR_S[i] = EMPTY_VALUE;
            }
        }
    }

    if (IsNewCandle || prev_calculated == 0)
    {
        if (EnableDrawArrows) DrawArrows(start);
    }

    if (EnableDrawArrows) DrawArrow(rates_total - 1);

    if (EnableNativeAlerts || EnableEmailAlerts || EnablePushAlerts || EnableSoundAlerts) CheckAlerts(rates_total, time);

    return rates_total;
}

void CheckAlerts(const int rates_total, const datetime &time[])
{
    if ((PriceType == PriceClose && ((Shift > 0 && iTime(Symbol(), MTF_Period, 0) > MathMax(LastAlertTimeBuy, LastAlertTimeSell)) || Shift == 0)) || // Classic check for Close price alerts.
         PriceType == PriceHighLow) // High/Low price - check only for signal repetition further below.
    {
        int curr_index = rates_total - 1 - Shift;
        // Find curr index for MTF.
        if (MTF_Mode && Shift == 1)
        {
            for (; curr_index > 0 && time[curr_index] >= iTime(Symbol(), MTF_Period, 0); curr_index--)
            {
            }
        }
        int prev_index = rates_total - 2 - Shift;
        // Find prev index for MTF.
        if (MTF_Mode)
        {
            for (; prev_index > 0 && time[prev_index] >= iTime(Symbol(), MTF_Period, Shift); prev_index--)
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
    string Text, TextNative;
    Text = "TBO: " + Symbol();
    if (MTF_Mode) Text += " - " + MTF_Suffix; 
    Text += " on " + GetTimeFrameString(Period()) + " - Crossed 0 from below.";
    TextNative = "TBO";
    if (MTF_Mode) TextNative += "(" + MTF_Suffix + ")";
    TextNative += ": Crossed 0 from below.";
    if (EnableNativeAlerts) Alert(TextNative);
    if (EnableEmailAlerts) SendMail("TBO Alert", Text);
    if (EnablePushAlerts) SendNotification(Text);
    if (EnableSoundAlerts) PlaySound(SoundFile);
    LastAlertTimeBuy = time;
    LastSignal = SIGNAL_BUY;
}

void IssueAlertsSell(datetime time)
{
    string Text, TextNative;
    Text = "TBO: " + Symbol();
    if (MTF_Mode) Text += " - " + MTF_Suffix;
    Text += " on " + GetTimeFrameString(Period()) + " - Crossed 0 from above.";
    TextNative = "TBO";
    if (MTF_Mode) TextNative += "(" + MTF_Suffix + ")";
    TextNative += ": Crossed 0 from above.";
    if (EnableNativeAlerts) Alert(TextNative);
    if (EnableEmailAlerts) SendMail("TBO Alert", Text);
    if (EnablePushAlerts) SendNotification(Text);
    if (EnableSoundAlerts) PlaySound(SoundFile);
    LastAlertTimeSell = time;
    LastSignal = SIGNAL_SELL;
}

void OnDeinit(const int reason)
{
    CleanChart();
    ChartRedraw();
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
    int j = i - Shift;

    if (j <= 0) return;

    // Find prev index for MTF when Shift == 0 because we might be in need of checking the 4th M1 bar inside the latest M5 bar against the last M1 bar of the previous M5 bar, for example.
    int curr_index = j;
    if (MTF_Mode && Shift == 1 && i == Bars(Symbol(), Period()) - 1)
    {
        datetime mtf_time = iTime(Symbol(), MTF_Period, 0);
        for (; curr_index > 0 && iTime(Symbol(), Period(), Bars(Symbol(), Period()) - 1 - curr_index) >= mtf_time; curr_index--)
        {
        }
    }
    int prev_index = curr_index - 1;
    if (MTF_Mode)
    {
        datetime mtf_time = (datetime)UpperTFTime[curr_index];
        for (; prev_index > 0 && iTime(Symbol(), Period(), Bars(Symbol(), Period()) - 1 - prev_index) >= mtf_time; prev_index--)
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
    if (NewCandleTime == iTime(Symbol(), 0, 0)) return false;
    else
    {
        NewCandleTime = iTime(Symbol(), 0, 0);
        return true;
    }
}

void DrawArrows(int start)
{
    for (int i = start; i < iBars(Symbol(), Period()) - 1; i++)
    {
        DrawArrow(i);
    }
}

void DrawArrow(int i)
{
    if (MTF_Mode)
    {
        if (Shift == 1 && i > 0)
        {
            if (UpperTFShift[i] == UpperTFShift[i - 1]) return; // If i isn't the first bar of the higher TF bar, skip.
        }
        else if (Shift == 0 && i < Bars(Symbol(), Period()) - 1)
        {
            if (UpperTFShift[i] == UpperTFShift[i + 1]) return; // If i isn't the last bar of the higher TF bar, skip.
        }
    }
    if (i == iBars(Symbol(), Period()) - 1) RemoveArrowCurr();

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
    datetime ArrowDate = iTime(Symbol(), Period(), iBars(Symbol(), Period()) - i - 1);
    string ArrowName = IndicatorName + "-ARWS-";
    double ArrowPrice = 0;
    int ArrowType = 0;
    color ArrowColor = 0;
    int ArrowAnchor = 0;
    int ArrowCode = 0;
    string ArrowDesc = "";
    if (Signal == SIGNAL_BUY)
    {
        ArrowPrice = iLow(_Symbol, _Period, iBars(_Symbol, _Period) - i - 1);
        ArrowType = ArrowBuy;
        ArrowColor = ArrowBuyColor;
        ArrowAnchor = ANCHOR_TOP;
        ArrowDesc = "BUY";
        ArrowName += "B";
    }
    else if (Signal == SIGNAL_SELL)
    {
        ArrowPrice = iHigh(_Symbol, _Period, iBars(_Symbol, _Period) - i - 1);
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
    int bars = Bars(Symbol(), Period());
    for (int i = 0; i < bars; i++)
    {
        datetime time = iTime(Symbol(), Period(), i);
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
    return StringSubstr(EnumToString(period), 7);
}

// iBarShift function with custom search for the bar when standard iBarShift fails.
int iBarShiftCustom(string symbol, ENUM_TIMEFRAMES tf, datetime time) // Always exact = false.
{
    int i = iBarShift(symbol, tf, time); // Try traditional first.
    if (i >= 0) return i; // Success.
    else i = 0; // Failed, start from zero.
    int bars = iBars(symbol, tf);
    while (iTime(symbol, tf, i) > time)
    {
        i++;
        if (i >= bars) return -1;
    }
    return i;
}
//+------------------------------------------------------------------+