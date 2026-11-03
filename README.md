# MERIT Prototype 2 — Blockchain Decision Verification

Standalone proof of concept for Jadon, Connor and Akram. The dashboard follows Prototype 1's layout, but its permission decisions and temporary blocks execute on an actual **local development blockchain**.

## Project focus and broader goals

Prototype 2 highlights blockchain decision verification as our primary focus for this stage of the MERIT project. It demonstrates using selected original MERIT contracts and verifying a confirmed access decision before releasing simulated sensor data. This focus represents one part of our broader SRS goals, which also include improving IoT access enforcement, addressing unauthorized access and excessive requests, and collecting data to evaluate the results. We plan to build on this prototype as we validate the inherited system and gain lab access, with implementation priorities guided by stakeholder feedback and feasibility for our team.

## Start on Windows

1. Extract the ZIP into a new folder. Keep it separate from Prototype 1 and the inherited MERIT project.
2. Install **Node.js 20 or newer**, including npm. Python and MetaMask are not required.
3. Double-click **SETUP_WINDOWS.bat** once. It installs pinned dependencies using the internet. Dependencies are deliberately excluded from the small ZIP.
4. Double-click **START_WINDOWS.bat**. Allow a short startup period for contract deployment.
5. The browser should open at **http://127.0.0.1:8766**. If not, open that address manually. Keep the terminal open; Ctrl+C stops it.

If a launcher fails, open a terminal in MERIT_Prototype_2 and run `npm ci --no-audit --no-fund`, then `node server.cjs`. On macOS/Linux use the same commands. To use another port: `node server.cjs --port 8767`. To suppress automatic browser opening: add `--no-browser`.

The UI binds only to 127.0.0.1. Ganache runs embedded in the process with **no public JSON-RPC listener**, no chain fork, and no public-network connection. It creates local test accounts and test ETH automatically. It does not request or use a wallet, real private keys, real funds, or lab access.

A Ganache message saying the optional µWS native module is unavailable and it is falling back to NodeJS can appear on newer Node versions. That fallback worked in our Node 24 test environment. If the dashboard loads and checks pass, this message does not prevent the demo from running.

## What this version actually reuses

**Unmodified files copied from your supplied Access_Control_Mechanism-main.zip:**

- `contracts/original/RoleToken.sol`
- `contracts/original/RoleBasedAccessControl.sol`

These are compiled and deployed locally. The original RoleToken handles group roles and mints the initial RTK balances. The original RoleBasedAccessControl supplies its same-group/global-member policy check. The source is copied byte for byte; PROVENANCE.json records original paths and SHA-256 hashes.

**New code:** `ReceiptDecisionGateway.sol`, the local server, receipt verifier, UI and tests. The new adapter uses those original role checks and adds request-correlated decision events and per-requester window/block state. It is not the inherited AccessControlContract or JudgeContract.

**Not deployed/integrated:** the inherited AccessControlContract, Judge, factory, registry, token penalty/reward workflow, Node IoT gateway, or physical sensor bridge. Role setup is a controlled local fixture. This is not validation of the full inherited deployment or of production authentication.

## Two-minute explanation

“This prototype runs MERIT's original role/token contracts on a local chain. A new adapter records each access decision. Our server waits for the transaction receipt and checks for a matching approval before returning sample data. We can distinguish transaction success from access approval, inspect real gas usage, and verify the adapter's blocking state.”

**Run all blockchain checks** starts a fresh deployment and produces seven checks:

1. A confirmed same-group A → B read returns sample sensor data.
2. A visitor → B request is denied, even though its transaction successfully executes (receipt status 1).
3. The sixth repeated A request triggers a block in the new adapter; subsequent requests return no data.
4. B can still read its own data while A is blocked.
5. Disabling the new adapter makes a request transaction revert (receipt status 0), with no verified decision and no data.
6. Advancing the development-chain clock demonstrates recovery.
7. Actual RTK balances remain unchanged during reads, because this adapter does not implement token deductions/rewards.

Expected: **7/7 checks**, with **13 access-request records**. Setup/admin/time-advance operations are not counted as access requests. The demo advances chain time by 11 seconds before the burst and again before recovery. Those are explicit development shortcuts, not measurements of natural recovery.

## Manual demonstration

- **Fresh deployment**, then **Approved read A → B**: show receipt status 1, verified approval, gas and sample readings.
- **Unapproved read visitor → B**: show receipt status 1 paired with DENY and no data. A mined transaction alone is not authorization.
- **Fresh deployment**, then **8 repeated reads**: show the new on-chain request count and block timestamp. Immediately use **Control read B → B**.
- **Advance local chain time +11 s**, then approved A read: show recovery. You may also wait in real time and send another transaction; the countdown is based on the latest mined block, not a continually ticking wall clock.
- Check **Disable new gateway contract**, then send a read: show a mined reverted transaction with actual gas used and no access-decision event. Uncheck to restore it; toggling itself is an admin transaction.

The default new adapter allows five requests in a fixed 10-chain-second window, then blocks for eight chain seconds. This is a fixed window beginning with the first request, unlike Prototype 1's sliding window. Pauses or slow execution can change which attempt exceeds the threshold. This is a bounded request-limit demo, not a full DoS-resistance test. The rule counts role-authorized and role-denied requests; requests made while disabled revert without updating state.

For unauthorized reads, the visitor is a registered member of another group, not an unknown external identity. A/B share the lab group. B is a regular member, A is a secondary group head, and the visitor is a primary head of a different group. The new adapter itself is registered to satisfy the inherited role contract's member-only read restrictions. The inherited global-primary-head rule remains unchanged; the fixture avoids two global heads in the denied case.

## Understanding the dashboard

- **On-chain setup:** original roles and actual RTK balances.
- **Transaction activity:** requester, mined receipt, verified access result and numbered attempts.
- **Receipt and state:** real transaction hash, request ID, block number, gas, test-chain fee, RTK before/after, and new adapter block timestamp.
- **Observed outcomes:** checks for this prototype, not lab acceptance tests.
- **Evidence:** exportable request records and the deployed contract addresses.

Repeated-read and full-demo actions finish their transactions first, then reveal recorded results every 0.4 seconds. That is presentation playback, not transaction timing. While transactions execute, the UI polls submission progress. There is no pretend mining delay or fabricated transaction hash.

## Receipt verification and data release

The Node server submits through the chosen local test signer, waits for a receipt, then checks:

- Receipt status is 1 and receipt destination is the deployed adapter.
- Exactly one Decision event comes from that adapter and matches the generated request ID, actual signer and intended sensor owner.
- That event explicitly permits access.

Only then is the fixed B sensor sample returned. DENY/BLOCK events, missing/mismatched events, status 0, and unconfirmed operations withhold it. Solidity transaction return values are not treated as mined access results. The adapter derives the requester from `msg.sender`; the browser is a local operator selecting a simulated device account, not device-authentication software.

Gas, receipt status and fee are actual local-chain values. RTK balances are read before/after the operation from the original contract. They are unchanged because **token penalties/rewards are not implemented here**. ETH gas fees and RTK are different units. `confirmation_ms` covers transaction submission/wait, receipt checks and the subsequent actor-state read; it excludes the initial before-state read, evidence writing and browser transfer. It is not a physical-device or public-chain performance benchmark.

## Evidence and persistence

CSV/JSON export includes the current run's access requests. The dashboard shows the most recent 100 records. Each evaluated request is also appended to `output/<run-id>.jsonl`; the output directory is created automatically. Sensor samples and private keys are excluded from evidence.

Fresh deployment creates new contract addresses and a new evidence run on the same development chain. Old contracts remain in that chain until you stop the process. Old on-disk run files remain. Restarting the server creates an entirely new in-memory chain with new test accounts. Old exported hashes refer to the old chain; their recorded receipts remain evidence, but they are not searchable on the new chain or a public explorer.

## Tests and compilation

Run `npm test`. Tests exercise an actual local EVM, verify receipt gas against queried receipts, and check successful denial, on-chain blocking, B control, mined revert, recovery, original role/balance reads, rejection of altered/missing/duplicated decision evidence, HTTP validation and exports.

Compiled ABI/bytecode artifacts are included so normal startup does not compile Solidity. To rebuild after edits, run `npm run compile`. Compiler and dependencies are pinned in package-lock.json. The lockfile marks Ganache’s bundled macOS-only fsevents package optional so npm ci also works on Windows/Linux. A clean npm ci install was verified on Linux. Source and artifact hashes are recorded in artifacts/manifest.json and checked at startup to avoid accidentally using stale bytecode.

## Scope and next integration step

This proves a small original-contract-backed verification path can work locally. It does not prove MERIT's inherited contracts/gateway have been repaired, validate inherited access-management permissions, or establish public-chain finality. One confirmation on an auto-mining development chain is the prototype's confirmation policy.

The next integration step is replacing the new adapter with a validated inherited access/Judge path, preserving the receipt matching and data-withholding checks, and testing actual token penalties and physical-device responses. Prototype 1 stays independent.

Reference documentation: https://docs.ethers.org/v6/single-page/ and https://github.com/ConsenSys-archive/ganache. These dependencies match the supplied project's development stack; this is a local educational prototype.
