# Ethscriptions L2 Derivation Node

This repo houses the Ruby app and Solidity predeploys that build the Ethscriptions chain on top of Ethereum. It started life as a Postgres-backed indexer; it now runs the derivation pipeline that turns L1 activity into canonical L2 blocks. You run it alongside an [ethscriptions-geth](https://github.com/ethscriptions-protocol/ethscriptions-geth) execution client.

## How the pipeline works
- Observe Ethereum L1 via JSON-RPC. The importer follows L1 blocks, receipts, and logs to find Ethscriptions intents (Data URIs plus ESIP events).
- Translate matching intents into deposit-style EVM transactions that call Ethscriptions predeploy contracts (storage, transfers, collections tooling).
- Send those transactions to geth through the Engine API, producing new L2 payloads. Geth seals the block, the predeploys mutate state, and the chain advances with the Ethscriptions rules baked in.

The result is an OP-style Stage-2 “app chain” that keeps Ethscriptions UX unchanged while providing Merkle-state, receipts, and compatibility with standard EVM tooling.

## What lives here
- **Ruby derivation app** — importer loop and Engine API driver; it is meant to stay stateless across runs.
- **Solidity contracts** — the Ethscriptions and token/collection predeploys plus Foundry scripts for generating the L2 genesis allocations. The Ethscriptions contract stores content with SSTORE2 chunked pointers and routes protocol calls through on-chain handlers.
- **Genesis + tooling** — scripts in `lib/` and `contracts/script/` to produce the genesis file consumed by geth.
- **Reference validator** — optional job queue that compares L2 receipts/storage against a reference Ethscriptions API to make sure derivation matches expectations.

Anything that executes L2 transactions (the `ethscriptions-geth` client) runs out-of-repo. This project focuses on deriving state and providing reference contracts.

## Run with Docker Compose
- Install Docker Desktop (includes the Compose plugin) and ensure you have access to an Ethereum L1 RPC endpoint.
- Copy `docker-compose/.env.example` to `docker-compose/.env`, then adjust the values for your environment (see below).
- From the repo root, bring the stack up:
  ```bash
  cd docker-compose
  docker compose --env-file .env up -d
  ```
- Follow logs while it syncs:
  ```bash
  docker compose logs -f importer
  ```
- Shut the stack down when you are done:
  ```bash
  docker compose down
  ```

### Environment quick reference
Key variables in `docker-compose/.env`:
- `COMPOSE_PROJECT_NAME`, `COMPOSE_BAKE` — control how Compose names resources and whether to use `docker buildx bake`.
- `JWT_SECRET` — 32-byte hex value shared with geth’s Engine API JWT config.
- `GENESIS_FILE`, `L1_NETWORK`, `L1_GENESIS_BLOCK` — define which genesis snapshot to mount and which L1 epoch anchors the rollup.
- `L1_RPC_URL` — archive-quality L1 RPC the importer will follow.
- `ETHSCRIPTIONS_API_BASE_URL`, `ETHSCRIPTIONS_API_KEY`, `VALIDATION_ENABLED` — toggle and configure the validator (point it at the API you want to reconcile against).
- `L1_PREFETCH_FORWARD`, `L1_PREFETCH_THREADS`, `PROFILE_IMPORT` — tune importer throughput and profiling output.
- `JOB_CONCURRENCY`, `JOB_THREADS` — SolidQueue worker sizing for validator jobs.
- `GC_MODE`, `STATE_HISTORY`, `TX_HISTORY`, `ENABLE_PREIMAGES` — pass-throughs to `ethscriptions-geth` to control archive depth and trie retention.
- `GETH_EXTERNAL_PORT` — port exposed on the host for the L2 RPC.

Any variable omitted from the file falls back to the defaults baked into the Compose file.

## Validator (optional)
The validator reads expected creations/transfers from your Ethscriptions API and compares them with receipts and storage pulled from geth. It pauses the importer when discrepancies appear so you can investigate mismatches or RPC issues. Enable it with `VALIDATION_ENABLED=true`, point it at `ETHSCRIPTIONS_API_BASE_URL`, and keep the SolidQueue workers running. The temporary SQLite databases in `storage/` and the SolidQueue worker pool exist only to support this reconciliation; once historical import is verified the goal is to remove that persistence and keep the derivation app stateless.

## Ethscriptions contracts in brief
- **Content storage** — Raw inscription bytes are chunked and written with SSTORE2; the contract keeps a hash index to prevent duplicate content and always returns the exact payload that appeared on L1.
- **Protocol hooks** — `registerProtocol` lets you associate a protocol name with a handler contract. When an ethscription is created or transferred, the Ethscriptions contract records the protocol and calls into the handler (`op_*` functions) so new behaviors can be layered on.
- **Token + collections plumbing** — Predeploys provide standard operations for fungible-style tokens and curated collections while still flowing through the same protocol registration pipeline.

## Finding your way around
- `app/services/` — derivation logic that turns L1 data into deposit transactions and steers Engine API calls.
- `app/models/` — Ethscription transaction models plus the validation result schema.
- `contracts/src/` — Ethscriptions, TokenManager, CollectionsManager predeploys.
- `contracts/script/` and `lib/` — genesis builders and helper utilities.
- `spec/` and `contracts/test/` — RSpec and Foundry tests.

Run `bundle exec rspec` for Ruby tests and `cd contracts && forge test` for solidity tests.

## Local development (optional)
If you want to modify the Ruby code outside of Docker, install Ruby 3.4.x, run `bundle install`, and use `bin/setup` to create local SQLite files. The importer still expects a running `ethscriptions-geth` and L1 RPC; the Compose stack is the recommended path for production-like runs.

## What stays the same for users
Ethscriptions behavior and APIs remain identical to the pre-chain era: inscribe and transfer as before, and existing clients can keep using the public API. The difference is that the data now lives in an L2 with cryptographic state, receipts, and interoperability with EVM tooling.

Questions or contributions? Open an issue or reach out in the Ethscriptions community channels.
