export interface WalletKeys {
  privateKey: string;
  publicKey: string;
  walletId: string;
}

export interface BridgeConfig {
  relayUrl: string;
  contractAddress: string;
  rpcUrl: string;
  privateKey: string;
}

export class Wallet {
  config: BridgeConfig;
  
  constructor(config: BridgeConfig) {
    this.config = config;
  }

  async balance() {
    return {
      wxMR: "0.0",
      pending: "0.0"
    };
  }

  async generateKeys(): Promise<WalletKeys> {
    return {
      privateKey: "mock_private_key",
      publicKey: "mock_public_key",
      walletId: Math.random().toString(36).substring(2, 15)
    };
  }
}