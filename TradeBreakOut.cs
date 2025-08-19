// -------------------------------------------------------------------------------
//   Red line crossing 0 from above is a support breakout signal.
//   Green line crossing 0 from below is a resistance breakout signal.
//   Multi-timeframe operation is supported.
//
//   Version 1.02
//   Copyright 2025, EarnForex.com
//   https://www.earnforex.com/indicators/TradeBreakOut/
// -------------------------------------------------------------------------------

using System;
using cAlgo.API;
using cAlgo.API.Internals;

namespace cAlgo
{
    [Levels(0)]
    [Indicator(ScalePrecision = 5, IsOverlay = false, TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
    public class TradeBreakOut_MTF : Indicator
    {
        [Parameter("Timeframe", DefaultValue = "Current")]
        public TimeFrame TimeFrameParam { get; set; }

        [Parameter("Period", DefaultValue = 50, MinValue = 1)]
        public int L { get; set; }

        [Parameter("Price Type", DefaultValue = PriceType.HighLow)]
        public PriceType PriceTypeParam { get; set; }

        [Parameter("Enable Native Alerts", DefaultValue = false, Group = "Alerts")]
        public bool EnableNativeAlerts { get; set; }

        [Parameter("Enable Email Alerts", DefaultValue = false, Group = "Alerts")]
        public bool EnableEmailAlerts { get; set; }

        [Parameter("Email Address", DefaultValue = "", Group = "Alerts")]
        public string EmailAddress { get; set; }

        [Parameter("Enable Sound Alerts", DefaultValue = false, Group = "Alerts")]
        public bool EnableSoundAlerts { get; set; }

        [Parameter("Sound Type", DefaultValue = SoundType.Announcement, Group = "Alerts")]
        public SoundType SoundType { get; set; }

        [Parameter("Trigger Candle", DefaultValue = TriggerCandle.CurrentCandle, Group = "Alerts")]
        public TriggerCandle TriggerCandleParam { get; set; }

        [Parameter("Enable Draw Arrows", DefaultValue = true, Group = "Arrows")]
        public bool EnableDrawArrows { get; set; }

        [Parameter("Buy Arrow Code", DefaultValue = "▲", Group = "Arrows")]
        public string ArrowBuy { get; set; }

        [Parameter("Sell Arrow Code", DefaultValue = "▼", Group = "Arrows")]
        public string ArrowSell { get; set; }

        [Parameter("Arrow Size", DefaultValue = 3, MinValue = 1, MaxValue = 5, Group = "Arrows")]
        public int ArrowSize { get; set; }

        [Parameter("Buy Arrow Color", DefaultValue = "Green", Group = "Arrows")]
        public Color ArrowBuyColor { get; set; }

        [Parameter("Sell Arrow Color", DefaultValue = "Red", Group = "Arrows")]
        public Color ArrowSellColor { get; set; }

        [Parameter("Indicator Short Name", DefaultValue = "TBO_MTF", Group = "Arrows")]
        public string IndicatorName { get; set; }

        [Output("Resistance Breakout", LineColor = "Green", PlotType = PlotType.Line)]
        public IndicatorDataSeries TBR_R { get; set; }

        [Output("Support Breakout", LineColor = "Red", PlotType = PlotType.Line)]
        public IndicatorDataSeries TBR_S { get; set; }

        // Alert tracking:
        private DateTime LastAlertTimeBuy = DateTime.MinValue;
        private DateTime LastAlertTimeSell = DateTime.MinValue;
        TradeSignal LastSignal = TradeSignal.Neutral;
        
        // MTF-related:
        private Bars mtfBars;
        private TimeFrame mtfTimeFrame;
        private bool UseMTF;
        private string mtfSuffix;

        private int Shift;  // A global-scope variable for TriggerCandle.
        
        public enum PriceType
        {
            Close,
            HighLow
        }

        public enum TriggerCandle
        {
            CurrentCandle = 0,
            ClosedCandle = 1
        }

        public enum TradeSignal
        {
            Buy = 1,
            Sell = -1,
            Neutral = 0
        }

        protected override void Initialize()
        {
            // Set MTF timeframe
            if (TimeFrameParam <= TimeFrame)
            {
                mtfTimeFrame = TimeFrame;
                UseMTF = false;
                mtfSuffix = mtfTimeFrame.ToString();
            }
            else
            {
                mtfTimeFrame = TimeFrameParam;
                UseMTF = true;
                mtfSuffix = "";
            }

            if (PriceTypeParam == PriceType.HighLow) Shift = 0; // Always latest bar for High/Low.
            else Shift = (int)TriggerCandleParam;

            mtfBars = MarketData.GetBars(mtfTimeFrame);
        }

        public override void Calculate(int index)
        {
            if (mtfBars == null || mtfBars.Count <= L)
            {
                TBR_R[index] = double.NaN;
                TBR_S[index] = double.NaN;
                return;
            }

            // Get the corresponding MTF bar index if needed.
            int mtfIndex = index;
            if (UseMTF)
            {
                DateTime currentTime = Bars.OpenTimes[index];
                mtfIndex = GetMTFIndex(currentTime);
            }

            if (mtfIndex < 0 || mtfIndex < L)
            {
                TBR_R[index] = double.NaN;
                TBR_S[index] = double.NaN;
                return;
            }

            // Calculate values using current or MTF data.
            if (PriceTypeParam == PriceType.Close)
            {
                double maxClose = GetMaximum(mtfBars.ClosePrices, mtfIndex - L, L);
                double minClose = GetMinimum(mtfBars.ClosePrices, mtfIndex - L, L);
                
                if (maxClose != 0)
                    TBR_R[index] = (mtfBars.ClosePrices[mtfIndex] - maxClose) / maxClose;
                else
                    TBR_R[index] = double.NaN;
                    
                if (minClose != 0)
                    TBR_S[index] = (mtfBars.ClosePrices[mtfIndex] - minClose) / minClose;
                else
                    TBR_S[index] = double.NaN;
            }
            else if (PriceTypeParam == PriceType.HighLow)
            {
                double maxHigh = GetMaximum(mtfBars.HighPrices, mtfIndex - L, L);
                double minLow = GetMinimum(mtfBars.LowPrices, mtfIndex - L, L);
                
                if (maxHigh != 0)
                    TBR_R[index] = (mtfBars.HighPrices[mtfIndex] - maxHigh) / maxHigh;
                else
                    TBR_R[index] = double.NaN;
                    
                if (minLow != 0)
                    TBR_S[index] = (mtfBars.LowPrices[mtfIndex] - minLow) / minLow;
                else
                    TBR_S[index] = double.NaN;
            }

            // If this is the last bar and MTF bar is still forming, update all bars belonging to current MTF bar.
            if (UseMTF && IsLastBar)
            {
                for (int i = Bars.Count - 1; i >= 0; i--)
                {
                    if (Bars.OpenTimes[i] >= mtfBars.OpenTimes[mtfIndex])
                    {
                        TBR_R[i] = TBR_R[index];
                        TBR_S[i] = TBR_S[index];
                    }
                    else break; // No need to check older bars.
                }
            }

            ProcessArrowsAndAlerts(index);            
        }

        private void ProcessArrowsAndAlerts(int index)
        {
            
            int index_mtf = index;
            if (UseMTF) index_mtf = GetMTFIndex(Bars.OpenTimes[index]);

            if (EnableDrawArrows && index > L + 1)
            {
                DrawArrow(index);
            }

            // Handle alerts only in real-time.
            if (IsLastBar)
            {
                CheckAlerts(index);
            }
        }

        private int GetMTFIndex(DateTime time)
        {
            if (mtfBars == null) return -1;

            // Find the MTF bar that contains this time.
            for (int i = mtfBars.Count - 1; i >= 0; i--)
            {
                if (mtfBars.OpenTimes[i] <= time) return i;
            }
            return -1;
        }

        // Gets checkIndex and prevIndex for alerts and arrows.
        private void GetIndexes(int index, ref int checkIndex, ref int prevIndex) 
        {
            if (!UseMTF) // Non-MTF:
            {
                checkIndex = index - Shift;
                prevIndex = checkIndex - 1;
            }
            else // MTF:
            {
                checkIndex = index;
                int index_mtf = GetMTFIndex(Bars.OpenTimes[index]);
                if (Shift == 1) // Need to find previous upper timeframe bar.
                {
                    for (int i = checkIndex - 1; i >= 0; i--)
                    {
                        if (Bars.OpenTimes[i] < mtfBars.OpenTimes[index_mtf])
                        {
                            checkIndex = i;
                            break;
                        }
                    }
                }
                prevIndex = checkIndex;
                for (int i = prevIndex - 1; i >= 0; i--)
                {
                    if (Bars.OpenTimes[i] < mtfBars.OpenTimes[index_mtf - Shift])
                    {
                        prevIndex = i;
                        break;
                    }
                }
            }

        }
        
        private void CheckAlerts(int index)
        {
            if (!EnableNativeAlerts && !EnableEmailAlerts && !EnableSoundAlerts) return;
            if (index < L + Shift + 1) return;

            int checkIndex = -1, prevIndex = -1;
            GetIndexes(index, ref checkIndex, ref prevIndex);

            DateTime currentTime = mtfBars.OpenTimes[mtfBars.Count - 1];
            if ((PriceTypeParam == PriceType.Close && ((Shift > 0 && currentTime > LastAlertTimeBuy && currentTime > LastAlertTimeSell) || Shift == 0)) || // Classic check for Close price alerts.
                 PriceTypeParam == PriceType.HighLow) // High/Low price - check only for signal repetition further below.
            {            
                bool NoBuySignal = false, NoSellSignal = false;
                // Buy signal:
                if (!double.IsNaN(TBR_R[checkIndex]) && !double.IsNaN(TBR_R[prevIndex]) && TBR_R[checkIndex] > 0 && TBR_R[prevIndex] <= 0)
                {
                    NoBuySignal = false;
                    if ((PriceTypeParam == PriceType.Close && LastSignal != TradeSignal.Buy) || (PriceTypeParam == PriceType.HighLow && currentTime > LastAlertTimeBuy))
                    {
                        string text = $"TBO: {Symbol.Name} - {mtfSuffix} on {TimeFrame.ToString()} - Crossed 0 from below.";
                        SendAlerts(text);
                        LastAlertTimeBuy = currentTime;
                        LastSignal = TradeSignal.Buy;
                    }
                }
                else NoBuySignal = true;
                // Sell signal:
                if (!double.IsNaN(TBR_S[checkIndex]) && !double.IsNaN(TBR_S[prevIndex]) && TBR_S[checkIndex] < 0 && TBR_S[prevIndex] >= 0)
                {
                    NoSellSignal = false;
                    if ((PriceTypeParam == PriceType.Close && LastSignal != TradeSignal.Sell) || (PriceTypeParam == PriceType.HighLow && currentTime > LastAlertTimeSell))
                    {
                        string text = $"TBO: {Symbol.Name} - {mtfSuffix} on {TimeFrame.ToString()} - Crossed 0 from above.";
                        SendAlerts(text);
                        LastAlertTimeSell = currentTime;
                        LastSignal = TradeSignal.Sell;
                    }
                }
                else NoSellSignal = true;
                if (NoBuySignal && NoSellSignal) LastSignal = TradeSignal.Neutral;
            }
        }

        private void SendAlerts(string message)
        {
            if (EnableNativeAlerts)
            {
                Notifications.ShowPopup("TradeBreakOut Alert", message, PopupNotificationState.Information);
            }
            
            if (EnableEmailAlerts && !string.IsNullOrEmpty(EmailAddress))
            {
                Notifications.SendEmail(EmailAddress, EmailAddress, "TBO Alert", message);
            }
            
            if (EnableSoundAlerts)
            {
                Notifications.PlaySound(SoundType);
            }
        }

        private void IsSignal(int index, ref bool signal_buy, ref bool signal_sell)
        {
            signal_buy = false;
            signal_sell = false;
            if (index < L + 1) return;

            int checkIndex = -1, prevIndex = -1;
            GetIndexes(index, ref checkIndex, ref prevIndex);

            if (!double.IsNaN(TBR_R[checkIndex]) && !double.IsNaN(TBR_R[prevIndex]))
            {
                if (TBR_R[checkIndex] > 0 && TBR_R[prevIndex] <= 0) signal_buy = true;
            }

            if (!double.IsNaN(TBR_S[checkIndex]) && !double.IsNaN(TBR_S[prevIndex]))
            {
                if (TBR_S[checkIndex] < 0 && TBR_S[prevIndex] >= 0) signal_sell = true;
            }
        }

        private void DrawArrow(int index)
        {
            if (index < L + 1) return;
            if (UseMTF)
            {
                if (Shift == 1 && index > 0)
                {
                    if (GetMTFIndex(Bars.OpenTimes[index]) == GetMTFIndex(Bars.OpenTimes[index - 1])) return; // If i isn't the first bar of the higher TF bar, skip.
                }
                else if (Shift == 0 && !IsLastBar)
                {
                    if (GetMTFIndex(Bars.OpenTimes[index]) == GetMTFIndex(Bars.OpenTimes[index + 1])) return; // If i isn't the last bar of the higher TF bar, skip.
                }
            }

            // Remove existing arrow at current position
            if (IsLastBar) RemoveArrow(index);

            bool signal_buy = false, signal_sell = false;
            IsSignal(index, ref signal_buy, ref signal_sell);
            TradeSignal signal = TradeSignal.Neutral;
            if (PriceTypeParam == PriceType.Close)
            {
                if (signal_buy) signal = TradeSignal.Buy;
                else if (signal_sell) signal = TradeSignal.Sell;
                if (signal == TradeSignal.Neutral) return;
                DrawArrowObject(signal, index);
            }
            else // High/Low
            {
                if (signal_buy) DrawArrowObject(TradeSignal.Buy, index);
                if (signal_sell) DrawArrowObject(TradeSignal.Sell, index);
            }
        }

        private void DrawArrowObject(TradeSignal signal, int index)
        {
            //index += Shift;
            DateTime arrowTime = Bars.OpenTimes[index];
            string arrowName = $"{IndicatorName}-ARWS";
            double arrowPrice;
            string arrowText;
            Color arrowColor;
            VerticalAlignment vAlign;
            string arrowDesc;

            if (signal == TradeSignal.Buy)
            {
                arrowPrice = Bars.LowPrices[index];
                arrowText = ArrowBuy;
                arrowColor = ArrowBuyColor;
                vAlign = VerticalAlignment.Bottom;
                arrowDesc = $"BUY ({mtfSuffix})";
                arrowName += "B";
            }
            else
            {
                arrowPrice = Bars.HighPrices[index];
                arrowText = ArrowSell;
                arrowColor = ArrowSellColor;
                vAlign = VerticalAlignment.Top;
                arrowDesc = $"SELL ({mtfSuffix})";
                arrowName += "S";
            }
            arrowName += $"-{arrowTime.Ticks}";
            int fontSize = 8 + (ArrowSize * 2);
            Chart.DrawText(arrowName, arrowText, index, arrowPrice, arrowColor);
            var textObj = Chart.FindObject(arrowName) as ChartText;
            if (textObj != null)
            {
                textObj.VerticalAlignment = vAlign;
                textObj.HorizontalAlignment = HorizontalAlignment.Center;
                textObj.FontSize = fontSize;
                textObj.Comment = arrowDesc;
            }
        }

        private void RemoveArrow(int index)
        {
            int index_mtf = GetMTFIndex(Bars.OpenTimes[index]);
            // Remove arrows on all bars that belong to this MTF bar.
            for (int i = index; i >= 0; i--)
            {
                if (Bars.OpenTimes[i] >= mtfBars.OpenTimes[index_mtf])
                {
                    DateTime arrowTime = Bars.OpenTimes[i];
                    string arrowName = $"{IndicatorName}-ARWSB-{arrowTime.Ticks}";
                    Chart.RemoveObject(arrowName);
                    arrowName = $"{IndicatorName}-ARWSS-{arrowTime.Ticks}";
                    Chart.RemoveObject(arrowName);
                }
                else break; // No need to check older bars.
            }
        }

        private double GetMaximum(DataSeries series, int startIndex, int count)
        {
            double max = double.MinValue;
            for (int i = startIndex; i < startIndex + count; i++)
            {
                if (i >= 0 && i < series.Count && series[i] > max)
                    max = series[i];
            }
            return max;
        }

        private double GetMinimum(DataSeries series, int startIndex, int count)
        {
            double min = double.MaxValue;
            for (int i = startIndex; i < startIndex + count; i++)
            {
                if (i >= 0 && i < series.Count && series[i] < min)
                    min = series[i];
            }
            return min;
        }
    }
}