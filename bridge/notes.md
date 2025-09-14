# TODO

- [ ] Listen for EVM contract state changes with RPC API
- [ ] Listen for XMR

# Monero operations

## Check whether a monero transaction exists and has been confirmed

From: <https://docs.getmonero.org/rpc-library/wallet-rpc/#check_tx_key>

check_tx_key¶

Check a transaction in the blockchain with its secret key.

Alias: None.

Inputs:

- txid - string; transaction id.
- tx_key - string; transaction secret key.
- address - string; destination public address of the transaction.

Outputs:

- confirmations - unsigned int; Number of block mined after the one with the transaction.
- in_pool - boolean; States if the transaction is still in pool or has been added to a block.
- received - unsigned int; Amount of the transaction.

Example:

```bash
curl -X POST http://127.0.0.1:18088/json_rpc -d \
    '{"jsonrpc":"2.0","id":"0","method":"check_tx_key","params":{"txid":"19d5089f9469db3d90aca9024dfcb17ce94b948300101c8345a5e9f7257353be","tx_key":"feba662cf8fb6d0d0da18fc9b70ab28e01cc76311278fdd7fe7ab16360762b06","address":"7BnERTpvL5MbCLtj5n9No7J5oE5hHiB3tVCK5cjSvCsYWD2WRJLFuWeKTLiXo5QJqt2ZwUaLy2Vh1Ad51K7FNgqcHgjW85o"}}' -H 'Content-Type: application/json'

```json
{
  "id": "0",
  "jsonrpc": "2.0",
  "result": {
    "confirmations": 0,
    "in_pool": false,
    "received": 1000000000000
  }
}
```

# Deployed contract

```
0xb087C13f03b0b5A303d919cBF4D732b835AFE434
```

# Docs

- Ethereum web3py: <https://web3py.readthedocs.io/en/stable/transactions.html>
- Monery python: <https://monero-python.readthedocs.io/en/latest/quickstart.html>
