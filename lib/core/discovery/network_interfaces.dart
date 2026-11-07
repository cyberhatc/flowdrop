import 'dart:io';

/// Gateways commonly used by phone and laptop hotspots.
///
/// When mDNS/UDP discovery is blocked these addresses are probed directly.
/// They are not trusted: the certificate fingerprint still has to match.
const List<String> hotspotGatewayAddresses = [
  '192.168.43.1', // Android tethering
  '172.20.10.1', // iOS Personal Hotspot
  '192.168.137.1', // Windows Mobile hotspot
  '192.168.0.1',
];

/// Interface name fragments that almost never carry peer traffic.
const List<String> _virtualInterfaceHints = [
  'docker',
  'veth',
  'br-',
  'vmnet',
  'vbox',
  'virtualbox',
  'hyper-v',
  'vethernet',
  'default switch',
  'tun',
  'tap',
  'utun',
  'wg',
  'wireguard',
  'tailscale',
  'zerotier',
  'hamachi',
  'loopback',
  'bluetooth',
];

bool isVirtualInterfaceName(String name) {
  final lower = name.toLowerCase();
  return _virtualInterfaceHints.any(lower.contains);
}

/// Returns the device's usable IPv4 addresses, best candidates first.
///
/// Virtual adapters (Docker, VPNs, VirtualBox, Hyper-V) are excluded: putting
/// them in a QR code only makes the connection attempts slower.
Future<List<String>> localIPv4Addresses({bool includeVirtual = false}) async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  final addresses = <String>{};
  for (final interface in interfaces) {
    if (!includeVirtual && isVirtualInterfaceName(interface.name)) continue;
    for (final address in interface.addresses) {
      if (address.type != InternetAddressType.IPv4) continue;
      if (address.isLoopback) continue;
      if (address.address.startsWith('169.254.')) continue;
      addresses.add(address.address);
    }
  }
  final list = addresses.toList()
    ..sort((a, b) {
      final aPrivate = isPrivateIPv4(a) ? 0 : 1;
      final bPrivate = isPrivateIPv4(b) ? 0 : 1;
      if (aPrivate != bPrivate) return aPrivate - bPrivate;
      return a.compareTo(b);
    });
  return list;
}

bool isPrivateIPv4(String address) {
  final parts = address.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
    return false;
  }
  final a = parts[0]!;
  final b = parts[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

/// The `/24` broadcast address for an IPv4 address, used by the UDP beacon.
String? broadcastAddressFor(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return null;
  return '${parts[0]}.${parts[1]}.${parts[2]}.255';
}
