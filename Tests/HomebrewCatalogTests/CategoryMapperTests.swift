import Foundation
import Testing
@testable import HomebrewCatalog

@Suite("CategoryMapper")
struct CategoryMapperTests {
    private struct TestItem: BrewItem {
        let id: String
        let name: String
        let desc: String?
        let homepage: String?
        let version: String? = nil
        let license: String? = nil
        let itemType: BrewItemType
        let tap: String? = nil
        let deprecated = false
        let deprecationDate: String? = nil
        let deprecationReason: String? = nil
        let disabled = false

        init(
            name: String,
            desc: String? = nil,
            homepage: String? = nil,
            itemType: BrewItemType = .formula
        ) {
            self.name = name
            self.id = name
            self.desc = desc
            self.homepage = homepage
            self.itemType = itemType
        }
    }

    @Test("homepage URLs do not force networking from http")
    func homepageDoesNotDriveNetworking() {
        let item = TestItem(
            name: "hello",
            desc: "A friendly greeting utility",
            homepage: "https://example.com/hello"
        )
        #expect(CategoryMapper.shared.mapItem(item) == .other)
    }

    @Test("cmake is developer tools, not networking via https homepage")
    func cmakeIsDeveloperTools() {
        let item = TestItem(
            name: "cmake",
            desc: "Cross-platform build system",
            homepage: "https://cmake.org/"
        )
        #expect(CategoryMapper.shared.mapItem(item) == .developerTools)
    }

    @Test("wget matches networking from name")
    func wgetIsNetworking() {
        let item = TestItem(
            name: "wget",
            desc: "Retrieve files from the web",
            homepage: "https://www.gnu.org/software/wget/"
        )
        #expect(CategoryMapper.shared.mapItem(item) == .networking)
    }

    @Test("ffmpeg is multimedia, not developer tools via ide substring")
    func ffmpegIsMultimedia() {
        let item = TestItem(
            name: "ffmpeg",
            desc: "Record, convert and stream audio and video",
            homepage: "https://ffmpeg.org/"
        )
        #expect(CategoryMapper.shared.mapItem(item) == .multimedia)
    }

    @Test("generic descriptions do not match single-letter science keyword")
    func noFalsePositiveFromLetterR() {
        let item = TestItem(
            name: "tree",
            desc: "Display directories as trees",
            homepage: "https://example.com"
        )
        #expect(CategoryMapper.shared.mapItem(item) != .science)
    }

    @Test("discord cask maps to communication")
    func discordCask() {
        let item = TestItem(
            name: "discord",
            desc: "Voice and text chat",
            homepage: "https://discord.com",
            itemType: .cask
        )
        #expect(CategoryMapper.shared.mapItem(item) == .communication)
    }
}
