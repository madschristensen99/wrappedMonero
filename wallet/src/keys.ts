export class Keys {
  static generate(): { privateKey: string; publicKey: string; address: string } {
    const privateKey = Math.random().toString(36).substring(2, 34);
    const publicKey = Math.random().toString(36).substring(2, 34);
    const address = "0x" + Math.random().toString(16).substring(2, 42);
    return { privateKey, publicKey, address };
  }
}