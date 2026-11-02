// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main struct BroadcastConfigurationTests {
    static func main() throws {
        var checks = 0, failures = 0
        func check(_ result: Bool, _ label: String) { checks += 1; print("\(result ? "PASS" : "FAIL") \(label)"); if !result { failures += 1 } }
        var config = BroadcastConfiguration()
        for title in ["First\nSecond", "First\rSecond", "First\r\nSecond"] {
            config.endpoint = "icecast://localhost:8000/live.mp3"; config.title = title
            do { _ = try config.arguments(); check(false, "Header line breaks rejected") } catch { check(true, "Header line breaks rejected") }
        }
        config.title = "NOIR"
        config.endpoint = "icecast://localhost:8000"
        do { _ = try config.arguments(); check(false, "Icecast mount is required") } catch { check(true, "Icecast mount is required") }
        config.endpoint = "icecasts://localhost:8443/live.mp3"; config.certificateAuthority = "/tmp/noir-test-ca.pem"
        let secure = try config.arguments()
        check(secure.contains("PUT") && secure.last?.hasPrefix("https://") == true && secure.contains("-tls_verify") && secure.contains("-verifyhost") && secure.contains(config.certificateAuthority), "Secure Icecast uses HTTP PUT with explicit certificate and hostname verification")
        config.kind = .shoutcast; config.endpoint = "shoutcast://localhost:8001"; config.password = "first\r\nsecond"
        do { _ = try ShoutcastConnection(configuration: config); check(false, "SHOUTcast login rejects embedded CRLF") } catch { check(true, "SHOUTcast login rejects embedded CRLF") }
        config.password = "local-test"; config.codec = .opus
        do { _ = try config.arguments(); check(false, "Unsupported SHOUTcast codec is rejected") } catch { check(true, "Unsupported SHOUTcast codec is rejected") }
        config.kind = .rtmp; config.endpoint = "rtmps://localhost:443/live/test"; config.codec = .aac
        let rtmp = try config.arguments()
        check(rtmp.contains("flv") && rtmp.contains("-tls_verify") && rtmp.contains("-verifyhost"), "RTMPS uses AAC/FLV with verification enabled")
        print("RESULT \(checks) broadcast configuration checks, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
