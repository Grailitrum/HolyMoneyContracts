module.exports = {
    networks: {
        fantom: {
            host: 'https://rpc.ankr.com/arbitrum',
            accounts: [`${process.env.METAMASK_KEY}`],
            // gasMultiplier: 2,
        },
    },
    compilers: {
        solc: {
            version: '^0.8.7',
        },
    },
};
