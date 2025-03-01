import XCTest
import Nimble
import ApolloInternalTestHelpers
@testable import CodegenCLI
import ArgumentParser
import ApolloCodegenLib

class GenerateTests: XCTestCase {

  // MARK: - Test Helpers

  func parse(_ options: [String]?) throws -> Generate {
    try Generate.parse(options)
  }

  // MARK: - Parsing Tests

  func test__parsing__givenParameters_none_shouldUseDefaults() throws {
    // when
    let command = try parse([])

    // then
    expect(command.inputs.path).to(equal(Constants.defaultFilePath))
    expect(command.inputs.string).to(beNil())
    expect(command.inputs.verbose).to(beFalse())
  }

  // MARK: - Generate Tests

  func test__generate__givenParameters_pathCustom_shouldBuildWithFileData() async throws {
    // given
    let inputPath = "./config.json"

    let options = [
      "--path=\(inputPath)"
    ]

    let mockConfiguration = ApolloCodegenConfiguration.mock()
    let mockFileManager = MockApolloFileManager(strict: true)

    mockFileManager.mock(closure: .contents({ path in
      let actualPath = URL(fileURLWithPath: path).standardizedFileURL.path
      let expectedPath = URL(fileURLWithPath: inputPath).standardizedFileURL.path

      expect(actualPath).to(equal(expectedPath))

      return try! JSONEncoder().encode(mockConfiguration)
    }))

    var didCallBuild = false
    MockApolloCodegen.buildHandler = { configuration in
      expect(configuration).to(equal(mockConfiguration))

      didCallBuild = true
    }

    // when
    let command = try parse(options)

    try await command._run(fileManager: mockFileManager.base, codegenProvider: MockApolloCodegen.self)

    // then
    expect(didCallBuild).to(beTrue())
  }

  func test__generate__givenParameters_stringCustom_shouldBuildWithStringData() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.mock()

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--string=\(jsonString)"
    ]

    var didCallBuild = false
    MockApolloCodegen.buildHandler = { configuration in
      expect(configuration).to(equal(mockConfiguration))

      didCallBuild = true
    }

    // when
    let command = try parse(options)

    try await command._run(codegenProvider: MockApolloCodegen.self)

    // then
    expect(didCallBuild).to(beTrue())
  }

  func test__generate__givenParameters_bothPathAndString_shouldBuildWithStringData() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.mock()

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--path=./path/to/file",
      "--string=\(jsonString)"
    ]

    var didCallBuild = false
    MockApolloCodegen.buildHandler = { configuration in
      expect(configuration).to(equal(mockConfiguration))

      didCallBuild = true
    }

    // when
    let command = try parse(options)

    try await command._run(codegenProvider: MockApolloCodegen.self)

    // then
    expect(didCallBuild).to(beTrue())
  }

  func test__generate__givenParameters_fetchDefault_shouldNotFetchSchema() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.mock()

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--string=\(jsonString)"
    ]

    var didCallBuild = false
    MockApolloCodegen.buildHandler = { configuration in
      expect(configuration).to(equal(mockConfiguration))

      didCallBuild = true
    }

    var didCallFetch = false
    MockApolloSchemaDownloader.fetchHandler = { configuration in
      expect(configuration).to(equal(mockConfiguration.schemaDownload))

      didCallFetch = true
    }

    // when
    let command = try parse(options)

    try await command._run(
      codegenProvider: MockApolloCodegen.self,
      schemaDownloadProvider: MockApolloSchemaDownloader.self
    )

    // then
    expect(didCallBuild).to(beTrue())
    expect(didCallFetch).to(beFalse())
  }

  func test__generate__givenParameters_fetchTrue_shouldFetchSchema() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.mock()

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--string=\(jsonString)",
      "--fetch-schema"
    ]

    var didCallBuild = false
    MockApolloCodegen.buildHandler = { configuration in
      expect(configuration).to(equal(mockConfiguration))

      didCallBuild = true
    }

    var didCallFetch = false
    MockApolloSchemaDownloader.fetchHandler = { configuration in
      expect(configuration).to(equal(mockConfiguration.schemaDownload))

      didCallFetch = true
    }

    // when
    let command = try parse(options)

    try await command._run(
      codegenProvider: MockApolloCodegen.self,
      schemaDownloadProvider: MockApolloSchemaDownloader.self
    )

    // then
    expect(didCallBuild).to(beTrue())
    expect(didCallFetch).to(beTrue())
  }

  func test__generate__givenParameters_fetchTrue_whenNilSchemaDownloadConfiguration_shouldThrow() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.init(
      schemaNamespace: "MockSchema",
      input: .init(
        schemaPath: "./schema.graphqls"
      ),
      output: .init(
        schemaTypes: .init(path: ".", moduleType: .swiftPackage())
      )
    )

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--string=\(jsonString)",
      "--fetch-schema"
    ]

    var didCallBuild = false
    MockApolloCodegen.buildHandler = { configuration in
      expect(configuration).to(equal(mockConfiguration))

      didCallBuild = true
    }

    var didCallFetch = false
    MockApolloSchemaDownloader.fetchHandler = { configuration in
      expect(configuration).to(equal(mockConfiguration.schemaDownload))

      didCallFetch = true
    }

    // when
    let command = try parse(options)

    // then
    await expect {
      try await command._run(
        codegenProvider: MockApolloCodegen.self,
        schemaDownloadProvider: MockApolloSchemaDownloader.self
      )
    }.to(throwError(
      localizedDescription: "Missing schema download configuration.",
      ignoringExtraCharacters: true
    ))

    expect(didCallBuild).to(beFalse())
    expect(didCallFetch).to(beFalse())
  }

  func test__generate__givenDefaultParameter_verbose_shouldSetLogLevelWarning() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.mock()

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--string=\(jsonString)"
    ]

    MockApolloCodegen.buildHandler = { configuration in }
    MockApolloSchemaDownloader.fetchHandler = { configuration in }

    var level: CodegenLogger.LogLevel?
    MockLogLevelSetter.levelHandler = { value in
      level = value
    }

    // when
    let command = try parse(options)

    try await command._run(
      codegenProvider: MockApolloCodegen.self,
      schemaDownloadProvider: MockApolloSchemaDownloader.self,
      logger: CodegenLogger.mock
    )

    // then
    await expect(level).toEventually(equal(.warning))
  }

  func test__generate__givenParameter_verbose_shouldSetLogLevelDebug() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.mock()

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--string=\(jsonString)",
      "--verbose"
    ]

    MockApolloCodegen.buildHandler = { configuration in }
    MockApolloSchemaDownloader.fetchHandler = { configuration in }

    var level: CodegenLogger.LogLevel?
    MockLogLevelSetter.levelHandler = { value in
      level = value
    }

    // when
    let command = try parse(options)

    try await command._run(
      codegenProvider: MockApolloCodegen.self,
      schemaDownloadProvider: MockApolloSchemaDownloader.self,
      logger: CodegenLogger.mock
    )

    // then
    await expect(level).toEventually(equal(.debug))
  }

  // MARK: Version Checking Tests

  func test__generate__givenCLIVersionMismatch_shouldThrowVersionMismatchError() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.mock()
    let fileManager = try testIsolatedFileManager()

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--string=\(jsonString)",
      "--verbose",
      "--path=\(fileManager.directoryURL.path)"
    ]

    MockApolloCodegen.buildHandler = { configuration in }
    MockApolloSchemaDownloader.fetchHandler = { configuration in }

    try fileManager.createFile(
      body: """
        {
          "pins": [
            {
              "identity": "apollo-ios",
              "kind" : "remoteSourceControl",
              "location": "https://github.com/apollographql/apollo-ios.git",
              "state": {
                "revision": "5349afb4e9d098776cc44280258edd5f2ae571ed",
                "version": "1.0.0-test.123"
              }
            }
          ],
          "version": 2
        }
        """,
      named: "Package.resolved"
    )

    // when
    let command = try parse(options)

    // then
    await expect {
      try await command._run(
        projectRootURL: fileManager.directoryURL,
        codegenProvider: MockApolloCodegen.self,
        schemaDownloadProvider: MockApolloSchemaDownloader.self
      )
    }.to(throwError())
  }

  func test__generate__givenCLIVersionMismatch_withIgnoreVersionMismatchArgument_shouldNotThrowVersionMismatchError() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.mock()
    let fileManager = try testIsolatedFileManager()

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--string=\(jsonString)",
      "--verbose",
      "--ignore-version-mismatch"
    ]

    MockApolloCodegen.buildHandler = { configuration in }
    MockApolloSchemaDownloader.fetchHandler = { configuration in }

    try fileManager.createFile(
      body: """
        {
          "pins": [
            {
              "identity": "apollo-ios",
              "kind" : "remoteSourceControl",
              "location": "https://github.com/apollographql/apollo-ios.git",
              "state": {
                "revision": "5349afb4e9d098776cc44280258edd5f2ae571ed",
                "version": "1.0.0-test.123"
              }
            }
          ],
          "version": 2
        }
        """,
      named: "Package.resolved"
    )

    // when
    let command = try parse(options)

    // then
    await expect {
      try await command._run(
        projectRootURL: fileManager.directoryURL,
        codegenProvider: MockApolloCodegen.self,
        schemaDownloadProvider: MockApolloSchemaDownloader.self
      )
    }.toNot(throwError())
  }

  func test__generate__givenNoPackageResolvedFile__shouldNotThrowVersionMismatchError() async throws {
    // given
    let mockConfiguration = ApolloCodegenConfiguration.mock()

    let jsonString = String(
      data: try! JSONEncoder().encode(mockConfiguration),
      encoding: .utf8
    )!

    let options = [
      "--string=\(jsonString)",
      "--verbose"
    ]

    MockApolloCodegen.buildHandler = { configuration in }
    MockApolloSchemaDownloader.fetchHandler = { configuration in }

    // when
    let command = try parse(options)

    // then
    await expect {
      try await command._run(
        codegenProvider: MockApolloCodegen.self,
        schemaDownloadProvider: MockApolloSchemaDownloader.self
      )
    }.toNot(throwError())
  }

}
