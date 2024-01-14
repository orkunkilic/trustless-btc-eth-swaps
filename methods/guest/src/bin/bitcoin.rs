#![no_main]

use std::io::Read;

use bitcoin::{block::Header, consensus::Decodable, Target};
use risc0_zkvm::guest::env;

risc0_zkvm::guest::entry!(main);

fn main() {
    // Read data sent from the application contract.
    let mut input_bytes = Vec::<u8>::new();
    env::stdin().read_to_end(&mut input_bytes).unwrap();

    let header = Header::consensus_decode_from_finite_reader(&mut &input_bytes[0..80]).unwrap();

    let target: Target = header.bits.into();

    header.validate_pow(target).unwrap();

    let hash = header.block_hash();

    let work: [u8; 32] = header.work().to_le_bytes();
    let work_u256: [u64; 4] = [
        u64::from_le_bytes(work[0..8].try_into().unwrap()),
        u64::from_le_bytes(work[8..16].try_into().unwrap()),
        u64::from_le_bytes(work[16..24].try_into().unwrap()),
        u64::from_le_bytes(work[24..32].try_into().unwrap()),
    ];

    env::commit_slice(&ethabi::encode(&[
        ethabi::Token::Bytes(hash[..].to_vec()),
        ethabi::Token::Bytes(header.merkle_root[..].to_vec()),
        ethabi::Token::Bytes(header.prev_blockhash[..].to_vec()),
        ethabi::Token::Uint(ethabi::ethereum_types::U256(work_u256)),
    ]));
}
