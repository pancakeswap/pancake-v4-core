# Pancake v4 Core

1. `0.8.26` in `foundry.toml` as it provides better gas optimization
2. `.prettierrc` explictly set `singleQuote: false` to overwrite any local dev's settings

## Running test

1. Install dependencies with `forge install` and `yarn`
2. Run test with `forge test --isolate`

See https://github.com/pancakeswap/pancake-v4-core/pull/35 on why `--isolate` flag is used.

## Update dependencies

1. Run `forge update`

## Deployment

The scripts are located in `/script` folder, deployed contract address can be found in `script/config`

### Pre-req: before deployment, the follow env variable needs to be set
```
// set script config: /script/config/{SCRIPT_CONFIG}.json
export SCRIPT_CONFIG=ethereum-sepolia

// set rpc url
export RPC_URL=https://

// private key need to be prefixed with 0x
export PRIVATE_KEY=0x

// optional. Only set if you want to verify contract on explorer
export ETHERSCAN_API_KEY=xx
```

### Execute

Refer to the script source code for the exact command

Example. within `script/01_DeployVault.s.sol`
```
// remove --verify flag if etherscan_api_key is not set
forge script script/01_DeployVault.s.sol:DeployVaultScript -vvv \
    --rpc-url $RPC_URL \
    --broadcast \
    --slow \
    --verify
```

Note you will need to update the `script/config/xxx.json` file to set the vault address that was created in order to deploy the PoolManagers.
