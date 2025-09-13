#!/usr/bin/env node
import { Command } from 'commander';
import chalk from 'chalk';
import { Wallet } from './wallet';
import { LatticeSigner } from './lattice-sig';
import { Keys } from './keys';

const program = new Command();

program
  .name('xmr-wallet')
  .description('wxMR bridge CLI')
  .version('1.0.0');

program
  .command('generate')
  .description('Generate new lattice key pair')
  .action(async () => {
    console.log(chalk.blue('Generating wallet...'));
    const keys = Keys.generate();
    console.log(chalk.green('Wallet generated!'));
    console.log('SK:', keys.privateKey);
    console.log('PK:', keys.publicKey);
    console.log('Address:', keys.address);
  });

program
  .command('burn')
  .description('Burn XMR and mint wxMR')
  .requiredOption('-a, --amount <amount>', 'Amount in atomic units')
  .requiredOption('-d, --dest <address>', 'Destination EVM address')
  .requiredOption('-k, --private-key <key>', 'Monero private key')
  .requiredOption('-r, --relay <url>', 'Relay service URL')
  .action(async (options) => {
    console.log(chalk.blue('Submitting burn request...'));
    
    try {
      const signer = new LatticeSigner();
      const signature = await LatticeSigner.signL2RS({
        privateKey: options.privateKey,
        amount: options.amount,
        destAddress: options.dest,
        ring: [],
        keyImage: "mock_key_image"
      });
      
      const payload = {
        tx_hash: "mock_tx_hash",
        l2rs_sig: JSON.stringify(signature),
        fhe_ciphertext: "mock_fhe_data",
        amount_commit: signature.amount_commit,
        key_image: signature.keyImage
      };
      
      console.log(chalk.green('Mock burn prepared!'));
      console.log('Payload:', JSON.stringify(payload, null, 2));
      console.log('Status check:', `${options.relay}/v1/status/mock-uuid`);
    } catch (error: any) {
      console.log(chalk.red('Burn failed:'), error.message);
    }
  });

program
  .command('status')
  .description('Check burn status')
  .requiredOption('-u, --uuid <uuid>', 'Transaction UUID')
  .requiredOption('-r, --relay <url>', 'Relay service URL')
  .action(async (options) => {
    try {
      const response = await fetch(`${options.relay}/v1/status/${options.uuid}`);
      const status = await response.json() as any;
      
      console.log('Status:', status.status);
      if (status.status === 'MINTED') {
        console.log('Ethereum tx:', status.eth_tx_hash);
        console.log('Amount:', status.amount);
      } else if (status.status === 'PENDING') {
        console.log('Transaction is still processing...');
      }
    } catch (error: any) {
      console.log(chalk.red('Status check failed:'), error.message);
    }
  });

program.parse();