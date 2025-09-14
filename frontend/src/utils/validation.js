export function isValidAddress(address) {
  if (!address) return false;
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}

export function isValidAmount(amount) {
  if (!amount || isNaN(amount)) return false;
  const num = parseFloat(amount);
  return num >= 0 && isFinite(num);
}

export function isValidSignature(signature) {
  if (!signature) return false;
  return signature.startsWith('0x') && signature.length === 132;
}

export function validateSignatures(v, r, s, requiredCount) {
  if (!Array.isArray(v) || !Array.isArray(r) || !Array.isArray(s)) {
    return { valid: false, message: 'Signatures must be arrays' };
  }
  
  if (v.length !== r.length || r.length !== s.length) {
    return { valid: false, message: 'Signature arrays must have equal length' };
  }
  
  if (v.length !== requiredCount) {
    return { valid: false, message: `Exactly ${requiredCount} signatures required` };
  }
  
  for (let i = 0; i < v.length; i++) {
    if (!v[i] || isNaN(parseInt(v[i])) || parseInt(v[i]) < 0 || parseInt(v[i]) > 28) {
      return { valid: false, message: `Invalid v signature: ${v[i]}` };
    }
    
    if (!r[i] || !r[i].startsWith('0x') || r[i].length !== 66) {
      return { valid: false, message: `Invalid r signature: ${r[i]}` };
    }
    
    if (!s[i] || !s[i].startsWith('0x') || s[i].length !== 66) {
      return { valid: false, message: `Invalid s signature: ${s[i]}` };
    }
  }
  
  return { valid: true, message: '' };
}