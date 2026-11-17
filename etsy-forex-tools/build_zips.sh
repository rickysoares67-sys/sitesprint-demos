#!/usr/bin/env bash
# Builds the Etsy download ZIPs into dist/. Run from etsy-forex-tools/.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf dist && mkdir dist
G=tools/PipCraft_Install_Guide.pdf
L=LICENSE_BUYER.txt
mk(){ name=$1; shift; zip -j -q "dist/$name.zip" "$@" "$L"; echo "dist/$name.zip"; }
mk PipCraft_TrendCloud_Indicator_MT5     indicators/PipCraft_TrendCloud.mq5 "$G"
mk PipCraft_SessionBoxes_Indicator_MT5   indicators/PipCraft_SessionBoxes.mq5 "$G"
mk PipCraft_LotSizeCalculator_MT5        indicators/PipCraft_LotSizeCalculator.mq5 "$G"
mk PipCraft_TrendRider_EA_MT5            robots/PipCraft_TrendRider_EA.mq5 "$G"
mk PipCraft_AsianBreakout_EA_MT5         robots/PipCraft_AsianBreakout_EA.mq5 "$G"
mk PipCraft_TradeManager_EA_MT5          robots/PipCraft_TradeManager_EA.mq5 "$G"
mk PipCraft_Forex_Trading_Journal        tools/PipCraft_Forex_Trading_Journal.xlsx
mk PipCraft_Forex_Cheat_Sheet            tools/PipCraft_Forex_Cheat_Sheet.pdf
# bundle keeps folders
zip -q -r dist/PipCraft_Complete_Forex_Toolkit.zip indicators robots tools/*.xlsx tools/*.pdf "$L"
echo dist/PipCraft_Complete_Forex_Toolkit.zip
