// dl-helper: the small native jobs of bin/deadlock, so a Mac needs neither Python nor Xcode to run it.
//   dl-helper displaymode                 the main display's mode as "<w>x<h>" (points)
//   dl-helper displaymode list            usable modes: "<w>x<h> hidpi=<0|1> refresh=<hz>"
//   dl-helper displaymode set <w>x<h>     switch for this login session (HiDPI preferred)
//   dl-helper vpk-maps <file.vpk>         the maps a mod carries (maps/<name>.vpk in its file tree)
//   dl-helper steam-build <appmanifest.acf> <appinfo.vdf>...   "<installed> <newest>" build ids of Deadlock
//                                         (newest from Steam's appinfo cache, 0 = unknown; no network)
//   dl-helper audio-output                "bluetooth", "builtin" or "other": the default output's connection
//   dl-helper audio-bt-guard              Bluetooth output + Bluetooth default mic -> built-in mic. Deadlock always
//                                         opens the default mic (voice chat); a Bluetooth headset whose own mic is
//                                         open drops to call quality (mono, 16 kHz). Prints what it changed.
import CoreAudio
import CoreGraphics
import Foundation

func fail(_ msg: String, _ code: Int32 = 2) -> Never {
  FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
  exit(code)
}

// MARK: display modes

func displayMode(_ args: [String]) {
  let display = CGMainDisplayID()
  let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
  let modes = (CGDisplayCopyAllDisplayModes(display, opts) as? [CGDisplayMode]) ?? []
  func desc(_ m: CGDisplayMode) -> String {
    "\(m.width)x\(m.height) hidpi=\(m.pixelWidth > m.width ? 1 : 0) refresh=\(Int(m.refreshRate))"
  }
  if args.isEmpty {
    if let m = CGDisplayCopyDisplayMode(display) { print("\(m.width)x\(m.height)") }
  } else if args[0] == "list" {
    for m in modes where m.isUsableForDesktopGUI() { print(desc(m)) }
  } else if args[0] == "set", args.count == 2 {
    let wh = args[1].split(separator: "x").compactMap { Int($0) }
    guard wh.count == 2 else { fail("usage: dl-helper displaymode set WxH") }
    let cands = modes.filter { $0.width == wh[0] && $0.height == wh[1] && $0.isUsableForDesktopGUI() }
    guard let m = cands.max(by: { ($0.pixelWidth, $0.refreshRate) < ($1.pixelWidth, $1.refreshRate) }) else {
      fail("no mode \(args[1])", 1)
    }
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { exit(1) }
    CGConfigureDisplayWithDisplayMode(cfg, display, m, nil)
    let r = CGCompleteDisplayConfiguration(cfg, .forSession)
    print(r == .success ? "set \(desc(m))" : "failed (\(r.rawValue))")
    exit(r == .success ? 0 : 1)
  } else {
    fail("usage: dl-helper displaymode [list | set WxH]")
  }
}

// MARK: little-endian reads

struct Bytes {
  let d: [UInt8]
  func u16(_ p: Int) -> Int { Int(d[p]) | Int(d[p + 1]) << 8 }
  func u32(_ p: Int) -> Int { u16(p) | u16(p + 2) << 16 }
  func u64(_ p: Int) -> UInt64 { UInt64(u32(p)) | UInt64(u32(p + 4)) << 32 }
  // NUL-terminated string at p; returns it and the position after the NUL
  func cstr(_ p: Int) -> (String, Int) {
    var e = p
    while e < d.count && d[e] != 0 { e += 1 }
    guard e < d.count else { return ("", d.count) }
    return (String(decoding: d[p..<e], as: UTF8.self), e + 1)
  }
}

func read(_ path: String, max: Int? = nil) -> Bytes? {
  guard let h = FileHandle(forReadingAtPath: path) else { return nil }
  defer { try? h.close() }
  let data = max.map { h.readData(ofLength: $0) } ?? h.readDataToEndOfFile()
  return Bytes(d: [UInt8](data))
}

// MARK: VPK file tree (v1 and v2 headers): extension / path / name triples, each entry 18 bytes + preload data

func vpkMaps(_ path: String) {
  guard let b = read(path, max: 1 << 24), b.d.count > 28 else { fail("can't read \(path)", 1) }
  var p = b.u32(4) == 2 ? 28 : 12
  func s() -> String { let (r, n) = b.cstr(p); p = n; return r }
  while p < b.d.count {
    let ext = s(); if ext.isEmpty { break }
    while p < b.d.count {
      let dir = s(); if dir.isEmpty { break }
      while p < b.d.count {
        let name = s(); if name.isEmpty { break }
        guard p + 18 <= b.d.count else { return }
        p += 18 + b.u16(p + 4)
        if ext == "vpk" && dir == "maps" { print(name) }
      }
    }
  }
}

// MARK: Steam: installed build (appmanifest) and the newest public build (appinfo.vdf v29: binary KeyValues with a
// string table)

func installedBuild(_ acf: String) -> Int {
  guard let text = try? String(contentsOfFile: acf, encoding: .utf8),
        let r = text.range(of: #""buildid"\s+"(\d+)""#, options: .regularExpression) else { return 0 }
  return Int(text[r].filter(\.isNumber)) ?? 0
}

enum KV { case dict([String: KV]), str(String), int(Int) }

func newestBuild(_ path: String, appid: Int) -> Int {
  guard let b = read(path), b.d.count > 16, b.u32(0) == 0x0756_4429 else { return 0 }
  let stoff = Int(b.u64(8))
  guard stoff + 4 <= b.d.count else { return 0 }
  var strs: [String] = []
  var p = stoff + 4
  for _ in 0..<b.u32(stoff) { let (s, n) = b.cstr(p); strs.append(s); p = n }
  func kv(_ start: Int) -> ([String: KV], Int)? {
    var p = start, out: [String: KV] = [:]
    while p < b.d.count {
      let t = b.d[p]; p += 1
      if t == 8 { return (out, p) }
      guard p + 4 <= b.d.count, b.u32(p) < strs.count else { return nil }
      let k = strs[b.u32(p)]; p += 4
      switch t {
      case 0: guard let (v, n) = kv(p) else { return nil }; out[k] = .dict(v); p = n
      case 1: let (v, n) = b.cstr(p); out[k] = .str(v); p = n
      case 2, 3, 4, 6: out[k] = .int(b.u32(p)); p += 4
      case 7: out[k] = .int(Int(truncatingIfNeeded: b.u64(p))); p += 8
      default: return nil
      }
    }
    return nil
  }
  p = 16
  while p + 8 <= stoff {
    let aid = b.u32(p), size = b.u32(p + 4)
    if aid == 0 { break }
    if aid == appid {
      // appid, size, infostate, last_updated, pics token, sha1, change number, binary sha1, then the KeyValues
      guard let (info, _) = kv(p + 8 + 4 + 4 + 8 + 20 + 4 + 20) else { return 0 }
      var cur: KV = .dict(info)
      for key in ["appinfo", "depots", "branches", "public", "buildid"] {
        guard case .dict(let d) = cur, let next = d[key] else { return 0 }
        cur = next
      }
      switch cur { case .str(let s): return Int(s) ?? 0; case .int(let i): return i; default: return 0 }
    }
    p += 8 + size
  }
  return 0
}

// MARK: audio devices

func audioProp(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {   // 32-bit properties only
  var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  var v: UInt32 = 0
  var size = UInt32(MemoryLayout<UInt32>.size)
  _ = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &v)
  return v
}

func audioDevices() -> [AudioDeviceID] {
  var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  var size: UInt32 = 0
  AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
  var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
  AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
  return ids
}

func audioName(_ d: AudioDeviceID) -> String {
  var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  var n: Unmanaged<CFString>?
  var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
  AudioObjectGetPropertyData(d, &addr, 0, nil, &size, &n)
  return n?.takeRetainedValue() as String? ?? "?"
}

func hasInput(_ d: AudioDeviceID) -> Bool {
  var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
  var size: UInt32 = 0
  return AudioObjectGetPropertyDataSize(d, &addr, 0, nil, &size) == noErr && size > 0
}

func audioTransport(_ d: AudioDeviceID) -> UInt32 { audioProp(d, kAudioDevicePropertyTransportType) }
func isBluetooth(_ d: AudioDeviceID) -> Bool {
  let t = audioTransport(d)
  return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
}

func audioCommand(_ cmd: String) {
  let sys = AudioObjectID(kAudioObjectSystemObject)
  let defIn = audioProp(sys, kAudioHardwarePropertyDefaultInputDevice)
  let defOut = audioProp(sys, kAudioHardwarePropertyDefaultOutputDevice)
  if cmd == "audio-output" {
    print(isBluetooth(defOut) ? "bluetooth" : audioTransport(defOut) == kAudioDeviceTransportTypeBuiltIn ? "builtin" : "other")
    return
  }
  guard isBluetooth(defOut), isBluetooth(defIn),
        let builtin = audioDevices().first(where: { audioTransport($0) == kAudioDeviceTransportTypeBuiltIn && hasInput($0) })
  else { return }
  var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
  var id = builtin
  if AudioObjectSetPropertyData(sys, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &id) == noErr {
    print("\(audioName(defOut)): mic -> \(audioName(builtin)) (the headset's own mic would drop it to call quality)")
  }
}

// MARK: main

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { fail("usage: dl-helper displaymode|vpk-maps|steam-build|audio-output|audio-bt-guard ...") }
args.removeFirst()
switch cmd {
case "displaymode":
  displayMode(args)
case "vpk-maps":
  guard args.count == 1 else { fail("usage: dl-helper vpk-maps <file.vpk>") }
  vpkMaps(args[0])
case "steam-build":
  guard args.count >= 1 else { fail("usage: dl-helper steam-build <appmanifest.acf> <appinfo.vdf>...") }
  let newest = args.dropFirst().map { newestBuild($0, appid: 1_422_450) }.max() ?? 0
  print("\(installedBuild(args[0])) \(newest)")
case "audio-output", "audio-bt-guard":
  audioCommand(cmd)
default:
  fail("unknown command \(cmd)")
}
