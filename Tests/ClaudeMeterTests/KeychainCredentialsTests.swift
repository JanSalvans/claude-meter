import Foundation
import Testing
@testable import ClaudeMeterCore

@Suite("Credencials del clauer")
struct KeychainCredentialsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("format niat amb camelCase")
    func formatNiat() throws {
        let data = Data("""
        { "claudeAiOauth": { "accessToken": "sk-test", "refreshToken": "r", "expiresAt": 1700003600000 } }
        """.utf8)
        let credentials = try KeychainCredentials.parse(data, now: now)
        #expect(credentials.accessToken == "sk-test")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_700_003_600))
    }

    @Test("isExpired es mesura contra l'hora real, no contra la injectada")
    func isExpiredAmbHoraReal() {
        let futura = ClaudeCredentials(accessToken: "x", expiresAt: Date().addingTimeInterval(3600))
        #expect(futura.isExpired == false)
        let passada = ClaudeCredentials(accessToken: "x", expiresAt: Date().addingTimeInterval(-1))
        #expect(passada.isExpired)
        #expect(ClaudeCredentials(accessToken: "x", expiresAt: nil).isExpired == false)
    }

    @Test("snake_case amb expires_in com a durada")
    func expiresIn() throws {
        let credentials = try KeychainCredentials.parse(
            Data(#"{ "access_token": "sk-altre", "expires_in": 3600 }"#.utf8),
            now: now
        )
        #expect(credentials.accessToken == "sk-altre")
        #expect(credentials.expiresAt == now.addingTimeInterval(3600))
    }

    @Test("sense data de caducitat")
    func senseCaducitat() throws {
        let credentials = try KeychainCredentials.parse(Data(#"{"accessToken":"x"}"#.utf8), now: now)
        #expect(credentials.expiresAt == nil)
        #expect(credentials.isExpired == false)
    }

    @Test("credencial caducada")
    func caducada() {
        let data = Data(#"{"accessToken":"x","expiresAt":1600000000}"#.utf8)
        #expect(throws: CredentialsError.expired(Date(timeIntervalSince1970: 1_600_000_000))) {
            _ = try KeychainCredentials.parse(data, now: now)
        }
    }

    @Test("JSON invàlid o sense token")
    func malformats() {
        #expect(throws: CredentialsError.self) {
            _ = try KeychainCredentials.parse(Data("no json".utf8), now: now)
        }
        #expect(throws: CredentialsError.malformed("no hi ha cap token d'accés")) {
            _ = try KeychainCredentials.parse(Data(#"{"foo":1}"#.utf8), now: now)
        }
    }

    @Test("la descripció no filtra el token")
    func descripcioSegura() throws {
        let credentials = try KeychainCredentials.parse(Data(#"{"accessToken":"sk-secret"}"#.utf8), now: now)
        #expect(credentials.description.contains("sk-secret") == false)
    }
}
