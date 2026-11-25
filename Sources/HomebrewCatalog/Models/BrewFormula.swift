import Foundation

struct BrewFormula: BrewItem, Codable, Sendable {
    let id: String
    let name: String
    let fullName: String?
    let tap: String?
    let desc: String?
    let license: String?
    let homepage: String?
    let versions: Versions?
    let revision: Int?
    let deprecated: Bool
    let deprecationDate: String?
    let deprecationReason: String?
    let disabled: Bool
    let disableDate: String?
    let disableReason: String?
    let dependencies: [String]?
    let buildDependencies: [String]?
    let testDependencies: [String]?
    let recommendedDependencies: [String]?
    let optionalDependencies: [String]?
    let conflictsWith: [String]?
    let caveats: String?
    let aliases: [String]?
    let versionedFormulae: [String]?
    let bottle: Bool?
    
    var itemType: BrewItemType { .formula }
    
    var version: String? { versions?.stable }
    
    struct Versions: Codable, Sendable {
        let stable: String?
        let head: String?
        let bottle: Bool?
    }
    
    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case tap
        case desc
        case license
        case homepage
        case versions
        case revision
        case deprecated
        case deprecationDate = "deprecation_date"
        case deprecationReason = "deprecation_reason"
        case disabled
        case disableDate = "disable_date"
        case disableReason = "disable_reason"
        case dependencies
        case buildDependencies = "build_dependencies"
        case testDependencies = "test_dependencies"
        case recommendedDependencies = "recommended_dependencies"
        case optionalDependencies = "optional_dependencies"
        case conflictsWith = "conflicts_with"
        case caveats
        case aliases
        case versionedFormulae = "versioned_formulae"
        case bottle
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        id = name
        fullName = try? container.decode(String.self, forKey: .fullName)
        tap = try? container.decode(String.self, forKey: .tap)
        desc = try? container.decode(String.self, forKey: .desc)
        license = try? container.decode(String.self, forKey: .license)
        homepage = try? container.decode(String.self, forKey: .homepage)
        versions = try? container.decode(Versions.self, forKey: .versions)
        revision = try? container.decode(Int.self, forKey: .revision)
        deprecated = try container.decodeIfPresent(Bool.self, forKey: .deprecated) ?? false
        deprecationDate = try? container.decode(String.self, forKey: .deprecationDate)
        deprecationReason = try? container.decode(String.self, forKey: .deprecationReason)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        disableDate = try? container.decode(String.self, forKey: .disableDate)
        disableReason = try? container.decode(String.self, forKey: .disableReason)
        dependencies = try? container.decode([String].self, forKey: .dependencies)
        buildDependencies = try? container.decode([String].self, forKey: .buildDependencies)
        testDependencies = try? container.decode([String].self, forKey: .testDependencies)
        recommendedDependencies = try? container.decode([String].self, forKey: .recommendedDependencies)
        optionalDependencies = try? container.decode([String].self, forKey: .optionalDependencies)
        conflictsWith = try? container.decode([String].self, forKey: .conflictsWith)
        caveats = try? container.decode(String.self, forKey: .caveats)
        aliases = try? container.decode([String].self, forKey: .aliases)
        versionedFormulae = try? container.decode([String].self, forKey: .versionedFormulae)
        bottle = try? container.decode(Bool.self, forKey: .bottle)
    }

    init(analyticsStubName name: String) {
        id = name
        self.name = name
        fullName = nil
        tap = nil
        desc = nil
        license = nil
        homepage = nil
        versions = nil
        revision = nil
        deprecated = false
        deprecationDate = nil
        deprecationReason = nil
        disabled = false
        disableDate = nil
        disableReason = nil
        dependencies = nil
        buildDependencies = nil
        testDependencies = nil
        recommendedDependencies = nil
        optionalDependencies = nil
        conflictsWith = nil
        caveats = nil
        aliases = nil
        versionedFormulae = nil
        bottle = nil
    }
}
