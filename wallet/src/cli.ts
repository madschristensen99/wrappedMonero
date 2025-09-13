#!/usr/bin/env node
import { Command } from 'commander';
import chalk from 'chalk';
import { generateWallet } from './wallet';
import { submitBurn } from './bridge';
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
    const wallet = await generateWallet();
    console.log(chalk.green('Wallet generated!'));
    console.log('SK:', wallet.sk);
    console.log('PK:', wallet.pk);
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
    
    const result = await submitBurn({
      amount: options.amount,
      destAddress: options.dest,
      privateKey: options.privateKey,
      relayUrl: options.relay
    });
    
    if (result.success) {
      console.log(chalk.green('Burn submitted successfully!'));
      console.log('Transaction ID:', result.uuid);
      console.log('Status check:', `${options.relay}/v1/status/${result.uuid}`);
    } else {
      console.log(chalk.red('Burn failed:'), result.error);
    }
  });

program
  .command('status')
  .description('Check burn status')
  .requiredOption('-u, --uuid <uuid>', 'Transaction UUID')
  .requiredOption('-r, --relay <url>', 'Relay service URL')
  .action(async (options) => {
    const Keys = Keys.getInstance();
    const status = await Keys.checkStatus(options.uuid, options.relay);
    
    console.log('Status:', status.status);
    if (status.status === 'MINTED') {
      console.log('Ethereum tx:', status.tx_hash_eth);
      console.log('Amount:', status.amount);
    }
  });

program.parse();