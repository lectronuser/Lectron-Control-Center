final List<int> _table = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// CRC-32 as ArduPilot's crc_crc32 and the PX4 bootloader compute it: reflected 0xEDB88320, no inversion.
int crc32Raw(Iterable<int> bytes, [int state = 0]) {
  for (final b in bytes) {
    state = _table[(state ^ b) & 0xFF] ^ (state >> 8);
  }
  return state;
}
