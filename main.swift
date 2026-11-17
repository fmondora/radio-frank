// RadioBar — radio su Sonos (anche più speaker insieme) e sul Mac, dalla barra dei menu.
// Build: ~/wip/personal/radio-frank/build.sh   Config: ~/.config/radiobar/config.json
import Cocoa
import AVFoundation

// MARK: - Config

let MAC = "Questo Mac"

struct Station: Codable { var name: String; var genre: String; var url: String }
struct Config: Codable {
    var speaker: String?          // formato vecchio, uno solo
    var speakers: [String]?       // destinazioni scelte, in ordine: il primo Sonos guida il gruppo
    var stations: [Station]
    var selected: [String] {
        get { speakers ?? [speaker ?? "Office"] }
        set { speakers = newValue; speaker = nil }
    }
}

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/radiobar/config.json")

let defaultConfig = Config(speaker: nil, speakers: ["Office"], stations: [
    Station(name: "Radio Caprice Klezmer", genre: "Klezmer", url: "http://79.120.39.202:8002/klezmer"),
    Station(name: "Chabad.org Jewish Music", genre: "Klezmer", url: "http://stream.radio.co/sdfd68a101/listen"),
    Station(name: "Radio Swiss Jazz", genre: "Jazz", url: "http://stream.srg-ssr.ch/m/rsj/mp3_128"),
    Station(name: "TSF Jazz", genre: "Jazz", url: "http://tsfjazz.ice.infomaniak.ch/tsfjazz-high.mp3"),
    Station(name: "Yoga Chill", genre: "Handpan & meditazione", url: "http://178.32.111.41:8027/stream-128kmp3-YogaChill"),
    Station(name: "Ambient Sleeping Pill", genre: "Handpan & meditazione", url: "http://radio.stereoscenic.com/asp-h"),
    Station(name: "Radio Art Tantra", genre: "Tantrico & indiano", url: "http://air.radioart.com/fTantra.mp3"),
    Station(name: "Mahakatha Radio (mantra, kirtan)", genre: "Tantrico & indiano", url: "http://mahakatharadio.com/api/station/live.mp3"),
    Station(name: "Radio Sangam Ganesha (mantra)", genre: "Tantrico & indiano", url: "http://radio2bindia.out.airtime.pro:8000/radio2bindia_a"),
])

func loadConfig() -> Config {
    if let d = try? Data(contentsOf: configURL), let c = try? JSONDecoder().decode(Config.self, from: d) { return c }
    saveConfig(defaultConfig)
    return defaultConfig
}

func saveConfig(_ c: Config) {
    try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    try? e.encode(c).write(to: configURL)
}

// MARK: - Sonos (UPnP/SOAP)

func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

func xmlUnescape(_ s: String) -> String {
    s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
     .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
     .replacingOccurrences(of: "&amp;", with: "&")
}

func tag(_ name: String, in s: String) -> String? {
    guard let a = s.range(of: "<\(name)>"), let b = s.range(of: "</\(name)>", range: a.upperBound..<s.endIndex) else { return nil }
    return String(s[a.upperBound..<b.lowerBound])
}

func httpSync(_ req: URLRequest) -> String? {
    var out: String?
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { d, _, _ in
        if let d = d { out = String(data: d, encoding: .utf8) }
        sem.signal()
    }.resume()
    _ = sem.wait(timeout: .now() + 5)
    return out
}

enum Sonos {
    @discardableResult
    static func soap(_ ip: String, _ service: String, _ action: String, _ args: [(String, String)] = []) -> String? {
        let path = service == "ZoneGroupTopology" ? "/ZoneGroupTopology/Control" : "/MediaRenderer/\(service)/Control"
        var req = URLRequest(url: URL(string: "http://\(ip):1400\(path)")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        req.setValue("\"urn:schemas-upnp-org:service:\(service):1#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        let body = args.map { "<\($0.0)>\(xmlEscape($0.1))</\($0.0)>" }.joined()
        req.httpBody = """
        <?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
        s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>\
        <u:\(action) xmlns:u="urn:schemas-upnp-org:service:\(service):1">\(body)</u:\(action)>\
        </s:Body></s:Envelope>
        """.data(using: .utf8)
        let r = httpSync(req)
        if let r = r, r.contains("s:Fault") { return nil }
        return r
    }

    static func playRadio(_ ip: String, _ st: Station) -> Bool {
        let rest = st.url.components(separatedBy: "://").dropFirst().joined(separator: "://")
        let uri = "x-rincon-mp3radio://" + rest
        let meta = """
        <DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" \
        xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/">\
        <item id="R:0/0/0" parentID="R:0/0" restricted="true"><dc:title>\(xmlEscape(st.name))</dc:title>\
        <upnp:class>object.item.audioItem.audioBroadcast</upnp:class>\
        <desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">SA_RINCON65031_</desc></item></DIDL-Lite>
        """
        guard soap(ip, "AVTransport", "SetAVTransportURI",
                   [("InstanceID", "0"), ("CurrentURI", uri), ("CurrentURIMetaData", meta)]) != nil else { return false }
        return play(ip)
    }

    static func play(_ ip: String) -> Bool { soap(ip, "AVTransport", "Play", [("InstanceID", "0"), ("Speed", "1")]) != nil }
    static func stop(_ ip: String) { soap(ip, "AVTransport", "Stop", [("InstanceID", "0")]) }
    static func pause(_ ip: String) {
        // Alcuni stream radio non accettano Pause: in quel caso Stop.
        if soap(ip, "AVTransport", "Pause", [("InstanceID", "0")]) == nil { stop(ip) }
    }

    static func volume(_ ip: String) -> Int? {
        soap(ip, "RenderingControl", "GetVolume", [("InstanceID", "0"), ("Channel", "Master")])
            .flatMap { tag("CurrentVolume", in: $0) }.flatMap { Int($0) }
    }

    static func setVolume(_ ip: String, _ v: Int) {
        soap(ip, "RenderingControl", "SetVolume",
             [("InstanceID", "0"), ("Channel", "Master"), ("DesiredVolume", String(max(0, min(100, v))))])
    }

    static func state(_ ip: String) -> String {
        soap(ip, "AVTransport", "GetTransportInfo", [("InstanceID", "0")])
            .flatMap { tag("CurrentTransportState", in: $0) } ?? "?"
    }

    /// (titolo stazione, brano in onda)
    static func nowPlaying(_ ip: String) -> (String?, String?) {
        let media = soap(ip, "AVTransport", "GetMediaInfo", [("InstanceID", "0")])
            .flatMap { tag("CurrentURIMetaData", in: $0) }.map(xmlUnescape)
        let pos = soap(ip, "AVTransport", "GetPositionInfo", [("InstanceID", "0")])
            .flatMap { tag("TrackMetaData", in: $0) }.map(xmlUnescape)
        let title = media.flatMap { tag("dc:title", in: $0) }.map(xmlUnescape)
        let song = pos.flatMap { tag("r:streamContent", in: $0) }.map(xmlUnescape).flatMap { $0.isEmpty ? nil : $0 }
        return (title, song)
    }

    struct Speaker { let ip: String; let uuid: String; let coordinator: String }

    /// Nome stanza -> speaker, via topologia dei gruppi (solo speaker visibili).
    static func discover() -> [String: Speaker] {
        guard let seed = ssdpFirstIP() else { return [:] }
        return topology(seed)
    }

    static func topology(_ seed: String) -> [String: Speaker] {
        guard let r = soap(seed, "ZoneGroupTopology", "GetZoneGroupState"),
              let state = tag("ZoneGroupState", in: r).map(xmlUnescape) else { return [:] }
        func attr(_ a: String, _ el: String) -> String? {
            guard let r = el.range(of: " \(a)=\"") else { return nil }
            return el[r.upperBound...].split(separator: "\"", maxSplits: 1).first.map(String.init)
        }
        var out: [String: Speaker] = [:]
        let groups = try! NSRegularExpression(pattern: "<ZoneGroup [^>]*>.*?</ZoneGroup>", options: .dotMatchesLineSeparators)
        let members = try! NSRegularExpression(pattern: "<ZoneGroupMember [^>]*>")
        for g in groups.matches(in: state, range: NSRange(state.startIndex..., in: state)) {
            let gs = String(state[Range(g.range, in: state)!])
            let coord = attr("Coordinator", gs) ?? ""
            for m in members.matches(in: gs, range: NSRange(gs.startIndex..., in: gs)) {
                let el = String(gs[Range(m.range, in: gs)!])
                if attr("Invisible", el) == "1" { continue }
                guard let name = attr("ZoneName", el), let uuid = attr("UUID", el),
                      let loc = attr("Location", el), let host = URL(string: loc)?.host else { continue }
                out[xmlUnescape(name)] = Speaker(ip: host, uuid: uuid, coordinator: coord)
            }
        }
        return out
    }

    /// Esce da qualunque gruppo (diventa autonomo).
    static func leave(_ ip: String) {
        soap(ip, "AVTransport", "BecomeCoordinatorOfStandaloneGroup", [("InstanceID", "0")])
    }

    /// Si aggancia al gruppo guidato da `coordinatorUUID`.
    @discardableResult
    static func join(_ ip: String, _ coordinatorUUID: String) -> Bool {
        soap(ip, "AVTransport", "SetAVTransportURI",
             [("InstanceID", "0"), ("CurrentURI", "x-rincon:\(coordinatorUUID)"), ("CurrentURIMetaData", "")]) != nil
    }

    /// Suona la stazione su uno o più speaker: il primo guida, gli altri si raggruppano.
    static func playGroup(_ sp: [Speaker], _ st: Station) -> Bool {
        guard let lead = sp.first else { return false }
        if lead.coordinator != lead.uuid { leave(lead.ip) }
        guard playRadio(lead.ip, st) else { return false }
        for m in sp.dropFirst() { join(m.ip, lead.uuid) }
        return true
    }

    static func ssdpFirstIP(timeout: Double = 3) -> String? {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(1900).bigEndian
        addr.sin_addr.s_addr = inet_addr("239.255.255.250")
        let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\n" +
                  "ST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"
        let deadline = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: 2048)
        while Date() < deadline {
            _ = msg.withCString { p in
                withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, p, strlen(p), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0, let s = String(bytes: buf[0..<n], encoding: .utf8),
               let line = s.components(separatedBy: "\r\n").first(where: { $0.uppercased().hasPrefix("LOCATION:") }),
               let host = URL(string: line.dropFirst(9).trimmingCharacters(in: .whitespaces))?.host {
                return host
            }
        }
        return nil
    }
}

// MARK: - Riproduzione sul Mac

final class MacPlayer: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    private var player: AVPlayer?
    private(set) var station: Station?
    private(set) var song: String?
    var volume: Float = 0.5 { didSet { volume = max(0, min(1, volume)); player?.volume = volume } }
    var onChange: (() -> Void)?

    var isPlaying: Bool { player.map { $0.timeControlStatus != .paused } ?? false }

    func play(_ st: Station) {
        stop()
        guard let url = URL(string: st.url) else { return }
        let item = AVPlayerItem(url: url)
        let out = AVPlayerItemMetadataOutput(identifiers: nil)
        out.setDelegate(self, queue: .main)
        item.add(out)
        let p = AVPlayer(playerItem: item)
        p.volume = volume
        p.play()
        player = p; station = st
    }

    /// Radio in diretta: dopo una pausa riparte dal vivo, non da dove si era fermata.
    func resume() { if let st = station { play(st) } }
    func pause() { player?.pause() }
    func stop() { player?.pause(); player = nil; song = nil }

    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let items = groups.flatMap { $0.items }
        if let t = items.first(where: { $0.identifier == .icyMetadataStreamTitle || $0.commonKey == .commonKeyTitle })?.value as? String,
           !t.isEmpty {
            song = t; onChange?()
        }
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    let q = DispatchQueue(label: "sonos")
    let mac = MacPlayer()
    var config = loadConfig()
    var speakers: [String: Sonos.Speaker] = [:]
    var station: Station?
    var current: (title: String?, song: String?, state: String, volumes: [String: Int]) = (nil, nil, "?", [:])
    var timer: Timer?

    var macOn: Bool { config.selected.contains(MAC) }
    var sonosSel: [Sonos.Speaker] { config.selected.filter { $0 != MAC }.compactMap { speakers[$0] } }
    var lead: Sonos.Speaker? { sonosSel.first }
    var sonosPlaying: Bool { current.state == "PLAYING" || current.state == "TRANSITIONING" }

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.delegate = self
        item.menu = menu
        mac.onChange = { [weak self] in self?.rebuild() }
        setIcon()
        rebuild()
        rediscover()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func setIcon() {
        let on = sonosPlaying || mac.isPlaying
        item.button?.image = NSImage(systemSymbolName: on ? "radio.fill" : "radio", accessibilityDescription: "Radio")
        item.button?.image?.isTemplate = true
    }

    func rediscover() {
        q.async {
            let s = Sonos.discover()
            DispatchQueue.main.async { self.speakers = s; self.rebuild(); self.refresh() }
        }
    }

    func refresh() {
        let sel = sonosSel
        guard let lead = sel.first else { current = (nil, nil, "?", [:]); setIcon(); rebuild(); return }
        q.async {
            let topo = Sonos.topology(lead.ip)
            let st = Sonos.state(lead.ip), (t, s) = Sonos.nowPlaying(lead.ip)
            var vols: [String: Int] = [:]
            for (name, sp) in self.speakers where sel.contains(where: { $0.uuid == sp.uuid }) { vols[name] = Sonos.volume(sp.ip) }
            DispatchQueue.main.async {
                if !topo.isEmpty { self.speakers = topo }
                self.current = (t, s, st, vols)
                self.setIcon()
                self.rebuild()
            }
        }
    }

    func menuWillOpen(_ m: NSMenu) { refresh() }

    func add(_ title: String, _ sel: Selector?, key: String = "", obj: Any? = nil, state: Bool = false) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self; i.representedObject = obj; i.state = state ? .on : .off
        if sel == nil { i.isEnabled = false }
        menu.addItem(i)
    }

    func rebuild() {
        menu.removeAllItems()
        let dove = config.selected.isEmpty ? "nessuna destinazione" : config.selected.joined(separator: " + ")
        let stato: String
        if lead != nil {
            stato = ["PLAYING": "▶︎ In onda", "PAUSED_PLAYBACK": "⏸ In pausa", "STOPPED": "⏹ Fermo",
                     "TRANSITIONING": "… Collegamento"][current.state] ?? "cerco gli speaker…"
        } else {
            stato = mac.isPlaying ? "▶︎ In onda" : "⏹ Fermo"
        }
        add("\(dove) — \(stato)", nil)
        if let t = lead != nil ? current.title : mac.station?.name { add("📻 \(t)", nil) }
        if let s = lead != nil ? current.song : mac.song { add("🎵 \(s)", nil) }
        menu.addItem(.separator())

        add("SUONA SU", nil)
        for name in speakers.keys.sorted() + [MAC] {
            add("   " + name, #selector(toggleSpeaker(_:)), obj: name, state: config.selected.contains(name))
        }
        if speakers.isEmpty { add("   nessun Sonos trovato", nil) }
        add("   Cerca speaker", #selector(doRediscover))
        menu.addItem(.separator())

        add("Play", #selector(doPlay), key: "p")
        add("Pausa", #selector(doPause), key: " ")
        add("Stop", #selector(doStop), key: "s")
        var vols = current.volumes.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
        if macOn { vols.append("Mac \(Int(mac.volume * 100))") }
        add("Volume +5" + (vols.isEmpty ? "" : "   (\(vols.joined(separator: " · ")))"), #selector(volUp), key: "+")
        add("Volume −5", #selector(volDown), key: "-")
        menu.addItem(.separator())

        var genre = ""
        let inOnda = station?.name ?? current.title
        for st in config.stations {
            if st.genre != genre { genre = st.genre; add(genre.uppercased(), nil) }
            add("   " + st.name, #selector(pick(_:)), obj: st, state: st.name == inOnda)
        }
        menu.addItem(.separator())
        add("Modifica stazioni…", #selector(editStations), key: ",")
        add("Ricarica stazioni", #selector(reloadStations), key: "r")
        menu.addItem(.separator())
        add("Esci", #selector(quit), key: "q")
    }

    func later() { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.refresh() } }

    func start(_ st: Station) {
        station = st
        if macOn { mac.play(st) }
        let sel = sonosSel
        guard !sel.isEmpty else { rebuild(); setIcon(); return }
        q.async {
            if !Sonos.playGroup(sel, st) {
                DispatchQueue.main.async { self.alert("Non riesco a suonare \(st.name) su \(sel.count > 1 ? "questi speaker" : "questo speaker").") }
            }
            DispatchQueue.main.async { self.later() }
        }
    }

    @objc func pick(_ s: NSMenuItem) {
        guard let st = s.representedObject as? Station else { return }
        if config.selected.isEmpty { alert("Scegli prima dove suonare, in «SUONA SU»."); return }
        start(st)
    }

    @objc func doPlay() {
        if let st = station ?? config.stations.first(where: { $0.name == current.title }) { start(st); return }
        if let l = lead { q.async { _ = Sonos.play(l.ip); DispatchQueue.main.async { self.later() } } }
    }
    @objc func doPause() {
        mac.pause()
        if let l = lead { q.async { Sonos.pause(l.ip); DispatchQueue.main.async { self.later() } } } else { rebuild(); setIcon() }
    }
    @objc func doStop() {
        mac.stop()
        if let l = lead { q.async { Sonos.stop(l.ip); DispatchQueue.main.async { self.later() } } } else { rebuild(); setIcon() }
    }
    func changeVolume(_ d: Int) {
        if macOn { mac.volume += Float(d) / 100 }
        let sel = sonosSel
        q.async {
            for sp in sel { Sonos.setVolume(sp.ip, (Sonos.volume(sp.ip) ?? 10) + d) }
            DispatchQueue.main.async { self.refresh() }
        }
    }
    @objc func volUp() { changeVolume(5) }
    @objc func volDown() { changeVolume(-5) }

    /// Aggiunge o toglie una destinazione; se sta suonando, la aggancia o la sgancia subito.
    @objc func toggleSpeaker(_ s: NSMenuItem) {
        guard let name = s.representedObject as? String else { return }
        let playing = sonosPlaying || mac.isPlaying
        let st = station ?? config.stations.first(where: { $0.name == current.title })
        if let i = config.selected.firstIndex(of: name) {
            let wasLead = name == lead.map { l in speakers.first { $0.value.uuid == l.uuid }?.key ?? "" }
            config.selected.remove(at: i); saveConfig(config)
            if name == MAC { mac.stop() }
            else if let sp = speakers[name] {
                let rest = sonosSel
                q.async {
                    Sonos.leave(sp.ip); Sonos.stop(sp.ip)
                    if wasLead, playing, let st = st, !rest.isEmpty { _ = Sonos.playGroup(rest, st) }
                    DispatchQueue.main.async { self.later() }
                }
            }
        } else {
            config.selected.append(name); saveConfig(config)
            if playing, let st = st {
                if name == MAC { mac.play(st) }
                else if let sp = speakers[name] {
                    let l = lead
                    q.async {
                        if let l = l, l.uuid != sp.uuid, self.sonosPlaying { Sonos.join(sp.ip, l.uuid) }
                        else { _ = Sonos.playGroup([sp], st) }
                        DispatchQueue.main.async { self.later() }
                    }
                }
            }
        }
        rebuild(); setIcon()
    }

    @objc func doRediscover() { rediscover() }
    @objc func editStations() { NSWorkspace.shared.open(configURL) }
    @objc func reloadStations() { let sel = config.selected; config = loadConfig(); config.selected = sel; rebuild(); refresh() }
    @objc func quit() { NSApp.terminate(nil) }

    func alert(_ t: String) {
        let a = NSAlert(); a.messageText = "RadioBar"; a.informativeText = t
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
}

// MARK: - CLI
// radiobar [--su Office,Spa] speakers | status | play "<stazione>" | pause | stop   (senza argomenti: barra dei menu)

var argv = Array(CommandLine.arguments.dropFirst())
var su: [String]?
if let i = argv.firstIndex(where: { $0 == "--su" || $0 == "-s" }), i + 1 < argv.count {
    su = argv[i + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    argv.removeSubrange(i...(i + 1))
}
if let cmd = argv.first {
    let cfg = loadConfig(), sp = Sonos.discover()
    if cmd == "speakers" { sp.sorted { $0.key < $1.key }.forEach { print($0.key, $0.value.ip) }; exit(0) }
    var names = (su ?? cfg.selected).filter { $0 != MAC }
    names = names.compactMap { n in sp.keys.first { $0.lowercased() == n.lowercased() } }
    guard !names.isEmpty else { print("nessuno speaker valido. Disponibili: \(sp.keys.sorted().joined(separator: ", "))"); exit(1) }
    let sel = names.compactMap { sp[$0] }, ip = sel[0].ip
    switch cmd {
    case "status":
        for (n, s) in zip(names, sel) {
            let (t, song) = Sonos.nowPlaying(s.ip)
            print(n, Sonos.state(s.ip), t ?? "-", song ?? "-", "vol", Sonos.volume(s.ip) ?? -1,
                  s.coordinator == s.uuid ? "" : "(nel gruppo di \(sp.first { $0.value.uuid == s.coordinator }?.key ?? "?"))")
        }
    case "play":
        let n = argv.dropFirst().joined(separator: " ").lowercased()
        if n.isEmpty { _ = Sonos.play(ip) }
        else if let st = cfg.stations.first(where: { $0.name.lowercased().contains(n) }) {
            print(Sonos.playGroup(sel, st) ? "▶︎ \(st.name) su \(names.joined(separator: " + "))" : "errore")
        } else { print("stazione non trovata") }
    case "pause": Sonos.pause(ip)
    case "stop": Sonos.stop(ip)
    case "ungroup": sel.forEach { Sonos.leave($0.ip) }
    default: print("uso: radiobar [--su Office,Spa] [speakers|status|play <stazione>|pause|stop|ungroup]")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
