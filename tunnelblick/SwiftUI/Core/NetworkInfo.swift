//
//  NetworkInfo.swift
//  Tunnelblick
//
//  Read-only information for the route display: what the configuration file says about the server, and which
//  network interface and address this Mac is using.
//
//  Copyright 2026 Tunnelblick contributors. GNU General Public License version 2.
//

import Foundation
import SystemConfiguration

/// The parts of an OpenVPN configuration file the interface shows.
struct ConfigurationFileInfo: Equatable {
    var remoteHost: String?
    var remotePort: String?
    var proto: String?          // "udp", "tcp", "tcp-client"...
    var device: String?         // "tun" or "tap"
    var cipher: String?
    var asksForUsernameAndPassword = false
    var hasPrivateKeyPassphrase = false     // Cannot be known from the file; left false
    var fileName: String?

    var isTCP: Bool { (proto ?? "").lowercased().hasPrefix("tcp") }

    /// "UDP 1194"
    var protocolAndPort: String {
        let protoText = (proto ?? "udp").uppercased().replacingOccurrences(of: "-CLIENT", with: "")
        if let remotePort { return protoText + " " + remotePort }
        return protoText
    }

    /// Reads the configuration file of a .tblk (Contents/Resources/config.ovpn) or a plain .ovpn/.conf file.
    /// Shared configurations can be readable only by root; then the result is empty.
    static func read(configurationPath path: String) -> ConfigurationFileInfo {
        var info = ConfigurationFileInfo()

        var filePath: String? = nil
        if path.hasSuffix(".tblk") {
            let resources = (path as NSString).appendingPathComponent("Contents/Resources")
            if let entries = try? FileManager.default.contentsOfDirectory(atPath: resources) {
                let candidates = entries.filter { $0.hasSuffix(".ovpn") || $0.hasSuffix(".conf") }.sorted()
                if let name = candidates.first(where: { $0 == "config.ovpn" }) ?? candidates.first {
                    filePath = (resources as NSString).appendingPathComponent(name)
                }
            }
        } else {
            filePath = path
        }

        guard let filePath, let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return info
        }
        info.fileName = (path as NSString).lastPathComponent

        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard let keyword = parts.first?.lowercased() else { continue }
            switch keyword {
            case "remote":
                if info.remoteHost == nil {
                    info.remoteHost = parts.count > 1 ? parts[1] : nil
                    if parts.count > 2 { info.remotePort = parts[2] }
                    if parts.count > 3 { info.proto = parts[3] }
                }
            case "port":
                if info.remotePort == nil, parts.count > 1 { info.remotePort = parts[1] }
            case "proto":
                if parts.count > 1 { info.proto = info.proto ?? parts[1] }
            case "dev":
                if parts.count > 1 { info.device = parts[1].hasPrefix("tap") ? "tap" : "tun" }
            case "cipher", "data-ciphers":
                if info.cipher == nil, parts.count > 1 { info.cipher = parts[1].split(separator: ":").first.map(String.init) }
            case "auth-user-pass":
                info.asksForUsernameAndPassword = true
            default:
                break
            }
        }

        if info.remotePort == nil { info.remotePort = "1194" }
        return info
    }
}

/// The network this Mac is using right now (primary interface).
struct LocalNetworkInfo: Equatable {
    var interfaceName: String?   // "Wi-Fi", "Ethernet"...
    var bsdName: String?         // "en0"
    var address: String?         // "192.168.1.34"
    var isWiFi = false

    static func current() -> LocalNetworkInfo {
        var info = LocalNetworkInfo()

        guard let store = SCDynamicStoreCreate(nil, "Tunnelblick" as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else {
            return info
        }

        // While a VPN that routes all traffic is up, the primary interface can be the tunnel; then show the physical one.
        var bsdName = global["PrimaryInterface"] as? String
        if let name = bsdName, name.hasPrefix("utun") || name.hasPrefix("tun") || name.hasPrefix("tap") {
            bsdName = physicalInterfaceWithAddress()
        }
        info.bsdName = bsdName

        if let bsdName, let interfaces = (SCNetworkInterfaceCopyAll() as NSArray) as? [SCNetworkInterface] {
            for interface in interfaces where (SCNetworkInterfaceGetBSDName(interface) as String?) == bsdName {
                info.interfaceName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?
                if let type = SCNetworkInterfaceGetInterfaceType(interface) {
                    info.isWiFi = ((type as String) == (kSCNetworkInterfaceTypeIEEE80211 as String))
                }
            }
        }

        if let bsdName {
            info.address = ipv4Address(of: bsdName)
        }
        return info
    }

    private static func ipv4Address(of interfaceName: String) -> String? {
        var result: String?
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let entry = current.pointee
            if let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               String(cString: entry.ifa_name) == interfaceName {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    result = String(cString: host)
                    break
                }
            }
            pointer = entry.ifa_next
        }
        return result
    }

    private static func physicalInterfaceWithAddress() -> String? {
        for candidate in ["en0", "en1", "en2", "en3", "en4", "en5"] where ipv4Address(of: candidate) != nil {
            return candidate
        }
        return nil
    }
}

/// Parses the VPN (tunnel) address from log text, e.g. from "PUSH_REPLY,...,ifconfig 10.8.0.6 255.255.255.0"
/// or "net_addr_v4_add: 10.8.0.6/24 dev utun5".
func vpnAddress(fromLog text: String) -> String? {
    let patterns = [
        #"net_addr_v4_add: ([0-9]{1,3}(?:\.[0-9]{1,3}){3})"#,
        #"ifconfig ([0-9]{1,3}(?:\.[0-9]{1,3}){3}) "#,
        #"/sbin/ifconfig \S+ ([0-9]{1,3}(?:\.[0-9]{1,3}){3})"#,
    ]
    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.matches(in: text, range: range).last,
           let r = Range(match.range(at: 1), in: text) {
            return String(text[r])
        }
    }
    return nil
}

/// Parses DNS servers pushed by the server from log text ("dhcp-option DNS 10.8.0.1").
func pushedDNSServers(fromLog text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: #"dhcp-option DNS ([0-9a-fA-F:.]+)"#) else { return [] }
    let range = NSRange(text.startIndex..., in: text)
    var seen: [String] = []
    for match in regex.matches(in: text, range: range) {
        if let r = Range(match.range(at: 1), in: text) {
            let address = String(text[r])
            if !seen.contains(address) { seen.append(address) }
        }
    }
    return seen
}
