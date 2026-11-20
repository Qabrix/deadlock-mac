// Deadlock Launcher: a window over bin/deadlock. First-run steps (Windows Steam, login and download, optional DLSS),
// then the path (Rosetta / ARM64), a custom map, practice helpers and display options. Commands run in the
// background; their output shows in the window. launcher/make-app.sh builds it.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

let appDir: String = {
  if let d = Bundle.main.object(forInfoDictionaryKey: "DLApp") as? String,
     FileManager.default.fileExists(atPath: d + "/bin/deadlock") { return d }
  return FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/deadlock-mac").path
}()
let cli = appDir + "/bin/deadlock"

struct GameMap: Hashable { let name: String, mod: String }

func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

func makeProcess(_ args: [String]) -> Process {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/zsh")
  p.arguments = [cli] + args
  var env = ProcessInfo.processInfo.environment
  env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
  p.environment = env
  return p
}

// a quick command: its output once it is done
func capture(_ args: [String]) -> String {
  let p = makeProcess(args), pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = Pipe()
  do { try p.run() } catch { return "" }
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  p.waitUntilExit()
  return String(decoding: data, as: UTF8.self)
}

func parseStatus(_ s: String) -> [String: String] {
  var d: [String: String] = [:]
  for line in s.split(separator: "\n") {
    guard let eq = line.firstIndex(of: "=") else { continue }
    d[String(line[..<eq])] = String(line[line.index(after: eq)...])
  }
  return d
}

final class Runner: ObservableObject {
  @Published var output = ""
  @Published var busy = false
  @Published var title = ""
  private var process: Process?

  func run(_ title: String, _ args: [String], done: (() -> Void)? = nil) {
    guard !busy else { return }
    busy = true
    self.title = title
    output = ""
    let p = makeProcess(args), pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { [weak self] h in
      let s = String(decoding: h.availableData, as: UTF8.self)
      guard !s.isEmpty else { return }
      DispatchQueue.main.async { self?.output += s }
    }
    p.terminationHandler = { [weak self] proc in
      pipe.fileHandleForReading.readabilityHandler = nil
      DispatchQueue.main.async {
        if proc.terminationStatus != 0 && self?.output.isEmpty == true {
          self?.output = "failed (exit \(proc.terminationStatus))"
        }
        self?.busy = false
        self?.process = nil
        done?()
      }
    }
    do { try p.run(); process = p } catch { output = "\(error)"; busy = false }
  }
}

struct LauncherView: View {
  @AppStorage("arm64") var arm64 = false
  @AppStorage("map") var mapKey = ""            // "<map> <mod>", "" = normal game
  @AppStorage("cheats") var cheats = true
  @AppStorage("parkour") var parkour = false
  @AppStorage("wheel") var wheel = false
  @AppStorage("dlss") var dlss = true
  @AppStorage("vsync") var vsync = false
  @AppStorage("framegen") var framegen = ""
  @AppStorage("hud") var hud = false
  @AppStorage("steamWindow") var steamWindow = false
  @State var status: [String: String] = [:]
  @State var maps: [GameMap] = []
  @State var running = false
  @StateObject var runner = Runner()
  let poll = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

  func flag(_ k: String) -> Bool { status[k] == "1" }
  var selectedMap: GameMap? { maps.first { "\($0.name) \($0.mod)" == mapKey } }
  var setupDone: Bool { flag("runtime_rosetta") && flag("windows_steam") && flag("game") }

  var playArgs: [String] {
    var a = ["play", arm64 ? "--arm64" : "--rosetta"]
    if let m = selectedMap { a += ["--map", m.name]; if !cheats { a.append("--no-cheats") } }
    if parkour { a.append("--parkour") }
    if wheel { a.append("--wheel") }
    if !dlss { a.append("--no-dlss") }
    if vsync { a.append("--vsync") }
    if !framegen.isEmpty && dlss && flag("framegen") { a += ["--framegen", framegen] }
    if hud { a.append("--hud") }
    if steamWindow && !arm64 { a.append("--steam-window") }
    return a
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if status.isEmpty {
        ProgressView().frame(maxWidth: .infinity)
      } else if !setupDone {
        setupSteps
      } else {
        options
      }
      if !runner.output.isEmpty || runner.busy { log }
      footer
    }
    .padding(16)
    .frame(width: 480)
    .onAppear { refresh(); loadMaps() }
    .onReceive(poll) { _ in checkRunning() }
  }

  var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Deadlock").font(.title2.bold())
      if !status.isEmpty {
        Text("\(status["model"] ?? "") · \(status["chip"] ?? "") · \(status["refresh"] ?? "60") Hz · macOS \(status["macos"] ?? "")")
          .font(.callout).foregroundStyle(.secondary)
        Text(status["hint"] ?? "").font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  // MARK: first run

  var setupSteps: some View {
    VStack(alignment: .leading, spacing: 10) {
      step(1, "Runtime", done: flag("runtime_rosetta"),
           note: "Missing: run the installer again (see the README).")
      step(2, "Windows Steam in Wine", done: flag("windows_steam"), action: ("Set up", { runner.run("Setup", ["setup"]) { refresh() } }),
           note: "Creates the Wine prefix and installs Windows Steam into it.")
      step(3, "Log in and download Deadlock", done: flag("game"), action: ("Open Steam", { runner.run("Steam", ["install"]) { refresh() } }),
           note: "Log in in Steam's window and confirm the install (~40 GB). This window notices when it's done.")
      dlssStep
    }
  }

  func step(_ n: Int, _ title: String, done: Bool, action: (String, () -> Void)? = nil, note: String) -> some View {
    HStack(alignment: .top) {
      Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
        .foregroundStyle(done ? .green : .secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).bold()
        if !done { Text(note).font(.caption).foregroundStyle(.secondary) }
      }
      Spacer()
      if !done, let action { Button(action.0, action: action.1).disabled(runner.busy) }
    }
  }

  var dlssStep: some View {
    HStack(alignment: .top) {
      Image(systemName: flag("dlss") ? "checkmark.circle.fill" : "sparkles")
        .foregroundStyle(flag("dlss") ? .green : .secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("DLSS (optional)").bold()
        if !flag("dlss") {
          Text("Needs one file from Apple's Game Porting Toolkit: download it (free Apple account), then pick the .dmg.")
            .font(.caption).foregroundStyle(.secondary)
          Link("developer.apple.com/games", destination: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!)
            .font(.caption)
        }
      }
      Spacer()
      if !flag("dlss") { Button("Choose .dmg…") { importGPTK() }.disabled(runner.busy) }
    }
  }

  // MARK: play options

  var options: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("", selection: $arm64) {
        Text("Rosetta").tag(false)
        Text("ARM64").tag(true)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .disabled(!flag("runtime_arm64"))
      if arm64 {
        Text("ARM64: no Rosetta for Wine and graphics. Mac Steam must be running and logged in; Windows Steam still downloads game updates.")
          .font(.caption).foregroundStyle(.secondary)
      }
      HStack {
        Picker("Map", selection: $mapKey) {
          Text("Normal game").tag("")
          if !maps.isEmpty { Divider() }
          ForEach(maps, id: \.self) { m in
            Text(m.name == m.mod ? m.name : "\(m.name)  (\(m.mod))").tag("\(m.name) \(m.mod)")
          }
        }
        Button { addMod() } label: { Image(systemName: "plus") }
          .buttonStyle(.borderless).help("Add a custom map (.vpk)")
      }
      if selectedMap != nil {
        Toggle("sv_cheats 1 on the map", isOn: $cheats)
        Text("Some maps replace the hero list while loaded; quit the game before a normal match.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Toggle("Parkour helpers  (Q checkpoint · E teleport · T stopwatch · H clear)", isOn: $parkour)
      Toggle("Scroll-wheel jump helpers  (Jump on Space and wheel)", isOn: $wheel)
      if flag("dlss") {
        Toggle("DLSS (MetalFX)", isOn: $dlss)
        if dlss && flag("framegen") {
          Picker("Frame generation", selection: $framegen) {
            Text("Off").tag("")
            Text("Fill missed refreshes").tag("auto")
            Text("Always (2x)").tag("1")
          }
        }
      } else {
        dlssStep
      }
      Toggle("VSync  (even pacing, a little more latency)", isOn: $vsync)
      Toggle("Metal HUD", isOn: $hud)
      if !arm64 { Toggle("Show Steam's window  (to answer its dialogs)", isOn: $steamWindow) }
    }
  }

  var log: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        if runner.busy { ProgressView().controlSize(.small) }
        Text(runner.title).font(.caption.bold())
        Spacer()
        if !runner.busy { Button("Clear") { runner.output = "" }.buttonStyle(.borderless).font(.caption) }
      }
      ScrollViewReader { proxy in
        ScrollView {
          Text(runner.output)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("end")
        }
        .frame(height: 110)
        .onChange(of: runner.output) { proxy.scrollTo("end", anchor: .bottom) }
      }
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
  }

  var footer: some View {
    HStack {
      Circle().fill(running ? .green : .secondary.opacity(0.4)).frame(width: 8, height: 8)
      Text(running ? "Deadlock is running" : "Not running").font(.callout).foregroundStyle(.secondary)
      Spacer()
      Menu("More") {
        Button("Update game files") { runner.run("Update", ["update", "--force"]) }
        Button("Open Windows Steam") { runner.run("Steam", ["steam"]) }
        Button("Open logs folder") {
          NSWorkspace.shared.open(URL(fileURLWithPath: (status["root"] ?? "") + "/logs"))
        }
        Button("Check setup") { runner.run("Doctor", ["doctor"]) { refresh() } }
      }
      .fixedSize()
      .disabled(runner.busy)
      Button("Kill") { runner.run("Kill", ["kill"]) { checkRunning() } }
      Button("Play") { runner.run("Play", playArgs) { checkRunning() } }
        .keyboardShortcut(.defaultAction)
        .disabled(running || runner.busy || !setupDone)
    }
  }

  // MARK: actions

  func refresh() {
    DispatchQueue.global().async {
      let s = parseStatus(capture(["status"]))
      DispatchQueue.main.async {
        status = s
        running = s["running"] == "1"
        if s["runtime_arm64"] != "1" { arm64 = false }
      }
    }
  }

  func checkRunning() {
    DispatchQueue.global().async {
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
      p.arguments = ["-qf", "[Dd]eadlock\\.exe"]
      try? p.run()
      p.waitUntilExit()
      let r = p.terminationStatus == 0
      DispatchQueue.main.async {
        running = r
        // during setup, notice when the download has finished
        if !setupDone && !runner.busy { refresh() }
      }
    }
  }

  func loadMaps() {
    DispatchQueue.global().async {
      let out = capture(["mods", "maps"])
      let m: [GameMap] = out.split(separator: "\n").compactMap { line in
        let f = line.split(separator: " ")
        return f.count == 2 ? GameMap(name: String(f[0]), mod: String(f[1])) : nil
      }
      DispatchQueue.main.async {
        maps = m
        if !mapKey.isEmpty && selectedMap == nil { mapKey = "" }
      }
    }
  }

  func pick(_ types: [UTType], _ message: String) -> URL? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = types
    panel.message = message
    return panel.runModal() == .OK ? panel.url : nil
  }

  func importGPTK() {
    guard let url = pick([UTType(filenameExtension: "dmg") ?? .data], "Game Porting Toolkit .dmg") else { return }
    runner.run("DLSS", ["gptk", url.path]) { refresh() }
  }

  func addMod() {
    guard let url = pick([UTType(filenameExtension: "vpk") ?? .data], "A custom map or mod (.vpk)") else { return }
    runner.run("Mods", ["mods", "install", url.path]) { loadMaps() }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DeadlockLauncher: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene {
    WindowGroup("Deadlock Launcher") { LauncherView() }
      .windowResizability(.contentSize)
  }
}
