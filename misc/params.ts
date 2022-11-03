export type Settings = {
    minStake: number,
    maxStake: number,
    timeInterval: number,    
    timeOffset: number,
};

export const settingsMap: Record<string, Settings> = {
    '1337': {
        minStake: 1_000_000, // 1 USDT
        maxStake: 5_000_000, // 5 USDT
        timeInterval: 60 * 5, // 5 mins 
        timeOffset: 0, // 11 hr (11 + 8 = 19 = 7 p.m.)
    },
    '80001': {
        minStake: 1_000_000, // 1 USDT
        maxStake: 5_000_000, // 5 USDT
        timeInterval: 60 * 5, // 5 mins 
        timeOffset: 0, // 11 hr (11 + 8 = 19 = 7 p.m.)
    },
    '137': {
        minStake: 1_000_000, // 1 USDT
        maxStake: 5_000_000, // 5 USDT
        timeInterval: 60 * 60 * 24, // 1 day 
        timeOffset: 60 * 60 * 11, // 11 hr (11 + 8 = 19 = 7 p.m.)
    },
};

export const usdtAddressMap: Record<string, string> = {
    '1337': "0x5FbDB2315678afecb367f032d93F642f64180aa3",
    '80001': "0xA02f6adc7926efeBBd59Fd43A84f4E0c0c91e832",
    '137': "0xc2132D05D31c914a87C6611C10748AEb04B58e8F",
};

export const btcAggregatorMap: Record<string, string> = {
    '1337': "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
    '80001': "0x007A22900a3B98143368Bd5906f8E17e9867581b",
    '137': "0xc907E116054Ad103354f2D350FD2514433D57F6f",
}