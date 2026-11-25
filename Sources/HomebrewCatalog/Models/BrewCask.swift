import Foundation

struct BrewCask: BrewItem, Codable, Sendable {
    let id: String
    let token: String
    let fullToken: String?
    let tap: String?
    let names: [String]?
    var name: String { names?.first ?? token }
    let desc: String?
    let homepage: String?
    let license: String?
    let url: String?
    let version: String?
    let sha256: String?
    let appcast: String?
    let artifacts: [Artifact]?
    let caveats: String?
    let dependsOn: DependsOn?
    let conflictsWith: Conflicts?
    let container: String?
    let autoUpdates: Bool?
    let deprecated: Bool
    let deprecationDate: String?
    let deprecationReason: String?
    let disabled: Bool
    let disableDate: String?
    let disableReason: String?
    let languages: [String]?
    let rubySourcePath: String?
    
    var itemType: BrewItemType { .cask }
    
    struct Artifact: Codable, Sendable {
        let app: [String]?
        let pkg: [String]?
        let binary: [BinaryArtifact]?
        let uninstall: [UninstallArtifact]?
        let zap: [ZapArtifact]?
        let quit: [String]?
        let delete: [String]?
        let rmdir: [String]?
        let trash: [String]?
        let signal: [String]?
        let login_item: [String]?
        let colorpicker: [String]?
        let font: [String]?
        let input_method: [String]?
        let internet_plugin: [String]?
        let prefpanef: [String]?
        let qlplugin: [String]?
        let mdimporter: [String]?
        let screen_saver: [String]?
        let service: [String]?
        let stage_only: [String]?
        let installer: [String]?
        let manpage: [String]?
        let postflight: String?
        let uninstall_postflight: String?
    }
    
    struct BinaryArtifact: Codable, Sendable {
        let path: String
        let target: String?
    }
    
    struct UninstallArtifact: Codable, Sendable {
        let quit: [String]?
        let delete: [String]?
        let rmdir: [String]?
        let trash: [String]?
        let signal: [String]?
    }
    
    struct ZapArtifact: Codable, Sendable {
        let trash: [String]?
        let delete: [String]?
        let rmdir: [String]?
        let signal: [String]?
    }
    
    struct DependsOn: Codable, Sendable {
        // API shape is e.g. {">=": ["12"]}; a wrong type here made the whole DependsOn decode fail.
        let macos: [String: [String]]?
        let arch: [String]?
        let cask: [String]?
        let formula: [String]?
    }
    
    struct Conflicts: Codable, Sendable {
        let cask: [String]?
        let formula: [String]?
    }
    
    enum CodingKeys: String, CodingKey {
        case token
        case fullToken = "full_token"
        case tap
        case names = "name"
        case desc
        case homepage
        case license
        case url
        case version
        case sha256
        case appcast
        case artifacts
        case caveats
        case dependsOn = "depends_on"
        case conflictsWith = "conflicts_with"
        case container
        case autoUpdates = "auto_updates"
        case deprecated
        case deprecationDate = "deprecation_date"
        case deprecationReason = "deprecation_reason"
        case disabled
        case disableDate = "disable_date"
        case disableReason = "disable_reason"
        case languages
        case rubySourcePath = "ruby_source_path"
    }
    
    init(from decoder: Decoder) throws {
        let decoderContainer = try decoder.container(keyedBy: CodingKeys.self)
        token = try decoderContainer.decode(String.self, forKey: .token)
        id = token
        fullToken = try? decoderContainer.decode(String.self, forKey: .fullToken)
        tap = try? decoderContainer.decode(String.self, forKey: .tap)
        names = try? decoderContainer.decode([String].self, forKey: .names)
        desc = try? decoderContainer.decode(String.self, forKey: .desc)
        homepage = try? decoderContainer.decode(String.self, forKey: .homepage)
        license = try? decoderContainer.decode(String.self, forKey: .license)
        url = try? decoderContainer.decode(String.self, forKey: .url)
        version = try? decoderContainer.decode(String.self, forKey: .version)
        sha256 = try? decoderContainer.decode(String.self, forKey: .sha256)
        appcast = try? decoderContainer.decode(String.self, forKey: .appcast)
        artifacts = try? decoderContainer.decode([Artifact].self, forKey: .artifacts)
        caveats = try? decoderContainer.decode(String.self, forKey: .caveats)
        dependsOn = try? decoderContainer.decode(DependsOn.self, forKey: .dependsOn)
        conflictsWith = try? decoderContainer.decode(Conflicts.self, forKey: .conflictsWith)
        container = try? decoderContainer.decode(String.self, forKey: .container)
        autoUpdates = try? decoderContainer.decode(Bool.self, forKey: .autoUpdates)
        deprecated = try decoderContainer.decodeIfPresent(Bool.self, forKey: .deprecated) ?? false
        deprecationDate = try? decoderContainer.decode(String.self, forKey: .deprecationDate)
        deprecationReason = try? decoderContainer.decode(String.self, forKey: .deprecationReason)
        disabled = try decoderContainer.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        disableDate = try? decoderContainer.decode(String.self, forKey: .disableDate)
        disableReason = try? decoderContainer.decode(String.self, forKey: .disableReason)
        languages = try? decoderContainer.decode([String].self, forKey: .languages)
        rubySourcePath = try? decoderContainer.decode(String.self, forKey: .rubySourcePath)
    }

    init(analyticsStubToken token: String) {
        id = token
        self.token = token
        fullToken = nil
        tap = nil
        names = [token]
        desc = nil
        homepage = nil
        license = nil
        url = nil
        version = nil
        sha256 = nil
        appcast = nil
        artifacts = nil
        caveats = nil
        dependsOn = nil
        conflictsWith = nil
        container = nil
        autoUpdates = nil
        deprecated = false
        deprecationDate = nil
        deprecationReason = nil
        disabled = false
        disableDate = nil
        disableReason = nil
        languages = nil
        rubySourcePath = nil
    }
}
