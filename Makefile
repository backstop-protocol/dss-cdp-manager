all    :; dapp --use solc:0.5.16 build
clean  :; dapp clean
test   :; dapp --use solc:0.5.16 test
deploy :; dapp create DssCdpManager
