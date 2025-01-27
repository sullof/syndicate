#!/usr/bin/env bash
# must be run from the root

rm -rf artifacts
rm -rf cache
npx hardhat compile

if [[ "$1" == "pool" ]]; then
# bin/deploy.sh pool localhost 1080 91252 7120725 3000 200
  SYN_PER_BLOCK=$3 BLOCK_PER_UPDATE=$4 BLOCK_MULTIPLIER=$5 QUICK_REWARDS=$6 WEIGHT=$7 \
    npx hardhat run scripts/deploy-$1.js --network $2
elif [[ "$1" == "syn" ]]; then
# bin/deploy.sh syn localhost 10000000000
  MAX_TOTAL_SUPPLY=$3 npx hardhat run scripts/deploy-$1.js --network $2
else
  npx hardhat run scripts/deploy-$1.js --network $2
fi
