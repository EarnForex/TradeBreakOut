//+------------------------------------------------------------------+
//|                                                TradeBreakOut.mq5 |
//|                             Copyright © 2013-2022, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2013-2022, www.EarnForex.com"
#property link      "https://www.earnforex.com/metatrader-indicators/TradeBreakOut/"
#property version   "1.01"

#property description "Red line crossing 0 from above is a support breakout signal."
#property description "Green line crossing 0 from below is a resistance breakout signal."

#property indicator_separate_window
#property indicator_buffers 2
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

enum enum_applied_price
{
    PriceClose, // Close
    PriceHighLow, // High/Low
};

enum enum_candle_to_check
{
    Current,
    Previous
};

input int L = 50; // Period
input enum_applied_price PriceType = PriceHighLow;
input bool EnableNativeAlerts  = false;
input bool EnableEmailAlerts   = false;
input bool EnablePushAlerts    = false;
input enum_candle_to_check TriggerCandle = Previous;

// Buffers
double TBR_R[], TBR_S[];

datetime LastAlertTime = D'01.01.1970';

void OnInit()
{
    SetIndexBuffer(0, TBR_R, INDICATOR_DATA);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, L);

    SetIndexBuffer(1, TBR_S, INDICATOR_DATA);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, L);

    IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
    IndicatorSetString(INDICATOR_SHORTNAME, "TBR (" + IntegerToString(L) + ")");
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
    int start;

    if (rates_total <= L) return 0;

    // Skip calculated bars.
    start = prev_calculated - 1;
    // First run.
    if (start < L) start = L;

    for (int i = L; i < rates_total; i++)
    {
        if (PriceType == PriceClose)
        {
            TBR_R[i] = (close[i] - close[ArrayMaximum(close, i - L, L)]) / close[ArrayMaximum(close, i - L, L)];
            TBR_S[i] = (close[i] - close[ArrayMinimum(close, i - L, L)]) / close[ArrayMinimum(close, i - L, L)];
        }
        else if (PriceType == PriceHighLow)
        {
            TBR_R[i] = (high[i] - high[ArrayMaximum(high, i - L, L)]) / high[ArrayMaximum(high, i - L, L)];
            TBR_S[i] = (low[i] - low[ArrayMinimum(low, i - L, L)]) / low[ArrayMinimum(low, i - L, L)];
        }
    }
    
    // Alerts
    if (((TriggerCandle > 0) && (time[rates_total - 1] > LastAlertTime)) || (TriggerCandle == 0))
    {
        string Text, TextNative;
        // Buy signal.
        if ((TBR_R[rates_total - 1 - TriggerCandle] > 0) && (TBR_R[rates_total - 2 - TriggerCandle] <= 0))
        {
            Text = "TBR: " + Symbol() + " - " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + " - Crossed 0 from below.";
            TextNative = "TBR: Crossed 0 from below.";
            if (EnableNativeAlerts) Alert(TextNative);
            if (EnableEmailAlerts) SendMail("TBR Alert", Text);
            if (EnablePushAlerts) SendNotification(Text);
            LastAlertTime = time[rates_total - 1];
        }
        // Sell signal.
        if ((TBR_S[rates_total - 1 - TriggerCandle] < 0) && (TBR_S[rates_total - 2 - TriggerCandle] >= 0))
        {
            Text = "TBR: " + Symbol() + " - " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + " - Crossed 0 from above.";
            TextNative = "TBR: Crossed 0 from above.";
            if (EnableNativeAlerts) Alert(TextNative);
            if (EnableEmailAlerts) SendMail("TBR Alert", Text);
            if (EnablePushAlerts) SendNotification(Text);
            LastAlertTime = time[rates_total - 1];
        }
    }
    
    return rates_total;
}
//+------------------------------------------------------------------+