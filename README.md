# Trustless BTC<>ETH Swaps Using ZK Proofs
### Repo template: Bonsai Foundry Template

> **Note: This software is not production ready. Do not use in production.**

## Dependencies
First, [install Rust] and [Foundry], and then restart your terminal. Next, you will need to install the `cargo risczero` tool.
We'll use `cargo binstall` to get `cargo-risczero` installed. See [cargo-binstall] for more details.

```bash
cargo install cargo-binstall
cargo binstall cargo-risczero
```

Next we'll need to install the `risc0` toolchain with:

```
cargo risczero install
```

### Test Your Project
- Use `cargo build` to test compilation of your zkVM program.
- Use `cargo test` to run the tests in your zkVM program.
- Use `forge test` to test your Solidity contracts and their interaction with your zkVM program.

### Configuring Bonsai
With the Bonsai proving service, you can produce a [Groth16 SNARK proof] that is verifiable on-chain.
You can get started by setting the following environment variables with your API key and associated URL.

```bash
export BONSAI_API_KEY="YOUR_API_KEY" 
export BONSAI_API_URL="BONSAI_URL"
```

Now if you run `forge test` with `RISC0_DEV_MODE=false`, the test will run as before, but will additionally use the fully verifying `BonsaiRelay` contract instead of `BonsaiTestRelay` and will request a SNARK receipt from Bonsai.

```bash
RISC0_DEV_MODE=false forge test
```