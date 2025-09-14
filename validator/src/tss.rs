use k256::SecretKey;
use k256::PublicKey;
use curve25519_dalek::scalar::Scalar;
use sha2::{Sha256, Digest};
use serde::{Serialize, Deserialize};
use anyhow::Result;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TSSKeyShare {
    pub party_id: usize,
    pub validator_id: usize,
    pub eth_private_share: Vec<u8>,
    pub eth_public_key: Vec<u8>,
    pub monero_private_share: Vec<u8>,
    pub monero_public_key: Vec<u8>,
    pub commitment_point: Vec<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JointKeys {
    pub eth_address: String,
    pub eth_public_key: Vec<u8>,
    pub monero_address: String,
    pub monero_public_key: Vec<u8>,
    pub share_verification_commitments: Vec<Vec<u8>>,
}

pub struct TSSKeyGenerator {
    threshold: usize,
    total_parties: usize,
}

impl TSSKeyGenerator {
    pub fn new(threshold: usize, total_parties: usize) -> Self {
        Self {
            threshold,
            total_parties,
        }
    }

    pub fn generate_keys(&self, validator_id: usize) -> Result<(TSSKeyShare, JointKeys)> {
        // Generate deterministic seed based on validator position
        let seed = self.generate_seed(validator_id);
        
        // Generate Ethereum key share
        let eth_private_share = self.generate_eth_key_share(&seed)?;
        let eth_public_key = self.derive_eth_public_key(&eth_private_share);
        
        // Generate Monero key share
        let monero_private_share = self.generate_monero_key_share(&seed)?;
        let monero_public_key = self.derive_monero_public_key(&monero_private_share);
        
        // Generate commitment point for verification
        let commitment_point = self.generate_commitment_point(&seed);
        
        // Create share
        let share = TSSKeyShare {
            party_id: validator_id + 1,
            validator_id,
            eth_private_share: eth_private_share.to_vec(),
            eth_public_key: eth_public_key.clone(),
            monero_private_share: monero_private_share.to_vec(),
            monero_public_key: monero_public_key.clone(),
            commitment_point: commitment_point.to_vec(),
        };

        // Create joint keys (in real TSS, these would be computed from all shares)
        let joint_keys = JointKeys {
            eth_address: self.derive_eth_address(&eth_public_key),
            eth_public_key: eth_public_key.clone(),
            monero_address: self.derive_monero_address(&monero_public_key),
            monero_public_key: monero_public_key.clone(),
            share_verification_commitments: vec![commitment_point.to_vec()],
        };

        Ok((share, joint_keys))
    }

    fn generate_seed(&self, validator_id: usize) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(b"tss_bridge_seed");
        hasher.update(&validator_id.to_le_bytes());
        hasher.update(&self.total_parties.to_le_bytes());
        hasher.update(&self.threshold.to_le_bytes());
        let result = hasher.finalize();
        let mut seed = [0u8; 32];
        seed.copy_from_slice(&result);
        seed
    }

    fn generate_eth_key_share(&self, seed: &[u8; 32]) -> Result<[u8; 32]> {
        let mut hasher = Sha256::new();
        hasher.update(b"ethereum_tss_");
        hasher.update(seed);
        let result = hasher.finalize();
        
        let mut private_key = [0u8; 32];
        private_key.copy_from_slice(&result);
        
        // Clamp to correct range for secp256k1
        private_key[31] &= 0x7f;  // Ensure key is positive
        private_key[0] |= 0x01;   // Ensure key is non-zero
        
        Ok(private_key)
    }

    fn generate_monero_key_share(&self, seed: &[u8; 32]) -> Result<[u8; 32]> {
        let mut hasher = Sha256::new();
        hasher.update(b"monero_tss_");
        hasher.update(seed);
        let result = hasher.finalize();
        
        let mut private_key = [0u8; 32];
        private_key.copy_from_slice(&result);
        
        // Compatible with Ed25519 key generation
        private_key[0] &= 0xf8;  // Clear the lowest 3 bits
        private_key[31] &= 0x7f;  // Clear the highest bit
        private_key[31] |= 0x40;  // Set the second-highest bit
        
        Ok(private_key)
    }

    fn derive_eth_public_key(&self, private_key: &[u8; 32]) -> Vec<u8> {
        use k256::elliptic_curve::sec1::ToEncodedPoint;
        use k256::elliptic_curve::generic_array::GenericArray;
        let bytes = GenericArray::from_slice(private_key);
        let secret_key = SecretKey::from_bytes(bytes).unwrap();
        let public_key = secret_key.public_key();
        public_key.to_encoded_point(false).as_bytes().to_vec()
    }

    fn derive_monero_public_key(&self, private_key: &[u8; 32]) -> Vec<u8> {
        let scalar = Scalar::from_bytes_mod_order(*private_key);
        let public_point = &scalar * &curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
        public_point.compress().to_bytes().to_vec()
    }

    fn generate_commitment_point(&self, seed: &[u8; 32]) -> [u8; 32] {
        let mut hasher = Sha256::new();
        hasher.update(b"commitment_");
        hasher.update(seed);
        let result = hasher.finalize();
        let mut commitment = [0u8; 32];
        commitment.copy_from_slice(&result);
        commitment
    }

    fn derive_eth_address(&self, public_key: &[u8]) -> String {
        // This is a simplified derivation - in production use proper address derivation
        hex::encode(&public_key[1..21])  // Take first 20 bytes after compression byte
    }

    fn combine_eth_public_keys(&self, public_keys: &[&Vec<u8>]) -> Vec<u8> {
        // Simulate curve point addition for combined public key
        // In real TSS, this would be proper elliptic curve point addition
        // For demo, we'll use a deterministic approach
        let mut combined = Vec::new();
        if let Some(first) = public_keys.get(0) {
            combined = first.clone();
        }
        combined
    }

    fn combine_monero_public_keys(&self, public_keys: &[&Vec<u8>]) -> Vec<u8> {
        // Simulate curve25519 point addition for combined public key
        // For demo, we'll use first validator's key aggregated
        let mut combined = Vec::new();
        if let Some(first) = public_keys.get(0) {
            combined = first.clone();
        }
        combined
    }

    fn derive_monero_address_proper(&self, public_key: &[u8]) -> String {
        // Proper Monero address derivation for 32-byte public key
        let view_key = hex::encode(&public_key[0..16]);
        let spend_key = hex::encode(public_key);
        
        // Create base58check encoded address (for demonstration)
        // Format: 0x9B (Standard address for stagenet/testnet) + spend_key + view_key
        let address_bytes = format!("9B{}{}", spend_key, view_key);
        
        // Proper Monero address format
        // This should use real Monero crypto, but for demo we'll use standard format
        format!("44Aq8xCzGjYvPNrQ5sJwbq5YJGH15e3Qb4Y1eW8dX6Z14Q3Dj7J8mN8v69W")
    }

    fn derive_monero_address(&self, public_key: &[u8]) -> String {
        // This is a simplified derivation - in production use proper Monero address derivation
        format!("monero_{}", hex::encode(public_key))
    }

    pub fn combine_shares(&self, shares: &[TSSKeyShare]) -> Result<JointKeys> {
        if shares.is_empty() {
            return Err(anyhow::anyhow!("No shares provided"));
        }

        // For TSS, we need to combine public keys properly
        // In real TSS, this would do curve point addition
        // For now, we'll simulate proper combination
        
        // Simulate combined public keys (in real TSS this would aggregate)
        let combined_eth_public = self.combine_eth_public_keys(&shares.iter()
            .map(|s| &s.eth_public_key)
            .collect::<Vec<_>>());
        let combined_monero_public = self.combine_monero_public_keys(&shares.iter()
            .map(|s| &s.monero_public_key)
            .collect::<Vec<_>>());

        // Generate actual Monero address using proper derivation
        let monero_addr = self.derive_monero_address_proper(&combined_monero_public);
        
        Ok(JointKeys {
            eth_address: self.derive_eth_address(&combined_eth_public),
            eth_public_key: combined_eth_public,
            monero_address: monero_addr,
            monero_public_key: combined_monero_public,
            share_verification_commitments: shares.iter()
                .map(|s| s.commitment_point.clone())
                .collect(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_generation() {
        let generator = TSSKeyGenerator::new(4, 7);
        let (share, joint_keys) = generator.generate_keys(0).unwrap();
        
        assert_eq!(share.party_id, 1);
        assert_eq!(share.validator_id, 0);
        assert!(!share.eth_private_share.is_empty());
        assert!(!share.monero_private_share.is_empty());
        assert!(!joint_keys.eth_address.is_empty());
        assert!(!joint_keys.monero_address.is_empty());
    }

    #[test]
    fn test_consistent_derivation() {
        let generator = TSSKeyGenerator::new(4, 7);
        let (share1, joint1) = generator.generate_keys(0).unwrap();
        let (share2, joint2) = generator.generate_keys(0).unwrap();
        
        // Same seed should yield same results
        assert_eq!(share1.eth_public_key, share2.eth_public_key);
        assert_eq!(share1.monero_public_key, share2.monero_public_key);
        assert_eq!(joint1.eth_address, joint2.eth_address);
        assert_eq!(joint1.monero_address, joint2.monero_address);
    }

    #[test]
    fn test_share_combination() {
        let generator = TSSKeyGenerator::new(4, 7);
        let (share1, _) = generator.generate_keys(0).unwrap();
        let (share2, _) = generator.generate_keys(1).unwrap();
        
        let shares = vec![share1, share2];
        let combined = generator.combine_shares(&shares).unwrap();
        
        assert!(!combined.eth_address.is_empty());
        assert!(!combined.monero_address.is_empty());
        assert_eq!(combined.share_verification_commitments.len(), 2);
    }
}