import {HardhatUserConfig} from 'hardhat/types';
import '@nomiclabs/hardhat-waffle';
import 'hardhat-deploy-fake-erc20';
import '@nomiclabs/hardhat-etherscan';
import 'dotenv/config';

const config: HardhatUserConfig = {
    solidity: {
        compilers: [
            {
                version: '0.8.7',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 50,
                    },
                },
            },
            {
                version: '0.8.0',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 50,
                    },
                },
            },
        ],
    },

    networks: {
        fantom: {
            url: 'https://rpc.ankr.com/arbitrum',
            accounts: [process.env.REACT_APP_METAMASK_KEY || ""],
            // gasMultiplier: 2,
        },
        arbitrumOne: {
            url: 'https://rpc.ankr.com/arbitrum',
            accounts: [process.env.REACT_APP_METAMASK_KEY || ""],
            // gasMultiplier: 2,
        },
    },
    etherscan: {
        // Your API key for Etherscan
        // Obtain one at https://etherscan.io/
        apiKey: {
            arbitrumOne: process.env.FTMSCAN_API_KEY,
        },
    },
};

export default config;
