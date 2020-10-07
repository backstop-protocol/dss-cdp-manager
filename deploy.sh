#!/usr/bin/env bash

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
#SCORING_MACHINE=$(dapp create ScoringMachine)

# Deploy BCdpScoreConnector
#B_CDP_SCORE_CONNECTOR=$(dapp create BCdpScoreConnector $SCORING_MACHINE)

ZERO_ADDRESS="0x0000000000000000000000000000000000000000"
# Deploy Jar
# ARGS = uint256 _roundId, uint256 _withdrawTimelock, address _connector, 
#        address _vat, bytes32[] memory _ilks, address[] memory _gemJoins
JAR=$(dapp create Jar 1 1000000000000000 $ZERO_ADDRESS $VAT [\"ETH-A\"] [\"$GEM_JOIN_ETH\"])

echo
echo "###### B.PROTOCOL ADDRESSES ######"
echo "SCORING_MACHINE=$SCORING_MACHINE"
echo "B_CDP_SCORE_CONNECTOR=$B_CDP_SCORE_CONNECTOR"

