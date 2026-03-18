export const CHAINS = {
  ethereumSepolia: {
    chainId: 11155111,
    name: 'Ethereum Sepolia',
    callbackProxy: '0xc9f36411C9897e7F959D99ffca2a0Ba7ee0D7bDA'
  },
  baseSepolia: {
    chainId: 84532,
    name: 'Base Sepolia',
    callbackProxy: '0xa6eA49Ed671B8a4dfCDd34E36b7a75Ac79B8A5a6'
  },
  reactiveLasna: {
    chainId: 5318007,
    name: 'Reactive Lasna',
    callbackProxy: '0x0000000000000000000000000000000000fffFfF'
  },
  reactiveMainnet: {
    chainId: 1597,
    name: 'Reactive Mainnet',
    callbackProxy: '0x0000000000000000000000000000000000fffFfF'
  }
} as const;
