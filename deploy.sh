#!/usr/bin/env bash

##### CONSTANTS #####
ONE_DAY=$(expr 60 \* 60 \* 24)
ONE_MONTH=$(expr 30 \* $ONE_DAY) # assume 30 days in a month
FIVE_MONTHS=$(expr 5 \* $ONE_MONTH)
ZERO_ADDRESS="0x0000000000000000000000000000000000000000"
#####################

JSON_FILE=config/$1.json

VAT=$(jq -r ".MCD_VAT" $JSON_FILE)
END=$(jq -r ".MCD_END" $JSON_FILE)
SPOT=$(jq -r ".MCD_SPOT" $JSON_FILE)
GEM_JOIN_ETH=$(jq -r ".MCD_JOIN_ETH_A" $JSON_FILE)
GEM_JOIN_WBTC=$(jq -r ".MCD_JOIN_WBTC_A" $JSON_FILE)


echo "###### MCD ADDRESSES ######"
echo VAT = $VAT
echo END = $END
echo SPOT = $SPOT
echo GEM_JOIN_ETH = $GEM_JOIN_ETH
echo GEM_JOIN_WBTC = $GEM_JOIN_WBTC
echo

# Deploy ScoringMachine
SCORING_MACHINE=$(dapp create ScoringMachine)

# Deploy BCdpScoreConnector
B_CDP_SCORE_CONNECTOR=$(dapp create BCdpScoreConnector $SCORING_MACHINE)

# Deploy JarConnector
#JAR_CONNECTOR=$(dapp create JarConnector )

# Deploy Jar
ILK_ETH=$(seth --from-ascii "ETH-A" | seth --to-bytes32)
NOW=$(date "+%s")
WITHDRAW_TIME_LOCK=$(expr $NOW + $ONE_MONTH)
# ctor args = _roundId, _withdrawTimelock, _connector, _vat, _ilks, _gemJoins
#JAR=$(dapp create Jar 1 $WITHDRAW_TIME_LOCK $ZERO_ADDRESS $VAT [$ILK_ETH] [$GEM_JOIN_ETH])

#### TODO BCdpManager -> Pool -> Jar -> JarConnector -> BCdpManager

echo
echo "###### B.PROTOCOL ADDRESSES ######"
echo "SCORING_MACHINE=$SCORING_MACHINE"
echo "B_CDP_SCORE_CONNECTOR=$B_CDP_SCORE_CONNECTOR"
echo "JAR=$JAR"