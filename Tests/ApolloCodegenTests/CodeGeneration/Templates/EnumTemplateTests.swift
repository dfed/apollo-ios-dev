import XCTest
import Nimble
@testable import ApolloCodegenLib
import ApolloCodegenInternalTestHelpers
import GraphQLCompiler

class EnumTemplateTests: XCTestCase {
  var subject: EnumTemplate!

  override func tearDown() {
    subject = nil

    super.tearDown()
  }

  // MARK: Helpers

  /// Convenience function to build the `EnumTemplate` `subject`.
  ///
  /// - Parameters:
  ///   - name: Enum definition name.
  ///   - values: A tuple that combines the value name and optional deprecation reason.
  ///   - config: Code generation configuration.
  private func buildSubject(
    name: String = "TestEnum",
    customName: String? = nil,
    documentation: String? = nil,
    values: [(String, String?, documentation: String?, customName: String?)] = [("ONE", nil, nil, nil), ("TWO", nil, nil, nil)],
    config: ApolloCodegenConfiguration = ApolloCodegenConfiguration.mock()
  ) {
    let enumType = GraphQLEnumType.mock(
      name: name,
      values: values.map({
        let enumValue = GraphQLEnumValue.mock(
          name: $0.0,
          deprecationReason: $0.1,
          documentation: $0.documentation
        )
        enumValue.name.customName = $0.customName
        return enumValue
      }),
      documentation: documentation
    )
    enumType.name.customName = customName
    subject = EnumTemplate(
      graphqlEnum: enumType,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  private func renderSubject() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  // MARK: Access Level Tests

  func test_render_givenModuleType_swiftPackageManager_generatesSwiftEnum_withPublicAccess() {
    // given
    buildSubject(config: .mock(.swiftPackage()))

    let expected = """
    public enum TestEnum: String, EnumType {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test_render_givenModuleType_other_generatesSwiftEnum_withPublicAccess() {
    // given
    buildSubject(config: .mock(.other))

    let expected = """
    public enum TestEnum: String, EnumType {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test_render_givenModuleType_embeddedInTarget_withInternalAccessModifier_generatesSwiftEnum_withInternalAccess() {
    // given
    buildSubject(config: .mock(.embeddedInTarget(name: "TestTarget", accessModifier: .internal)))

    let expected = """
    enum TestEnum: String, EnumType {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test_render_givenModuleType_embeddedInTarget_withPublicAccessModifier_generatesSwiftEnum_withPublicAccess() {
    // given
    buildSubject(config: .mock(.embeddedInTarget(name: "TestTarget", accessModifier: .public)))

    let expected = """
    enum TestEnum: String, EnumType {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: Casing Tests

  func test_render_givenSchemaEnum_generatesSwiftEnumNameFirstUppercased() throws {
    // given
    buildSubject(name: "anEnum")

    let expected = """
    enum AnEnum: String, EnumType {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test_render_givenOption_caseConversionStrategy_camelCase_generatesSwiftEnumValues_convertedToCamelCase() {
    // given
    buildSubject(
      name: "casedEnum",
      values: [
        // Mixed case
        ("lowercase", nil, nil, nil),
        ("UPPERCASE", nil, nil, nil),
        ("Capitalized", nil, nil, nil),
        ("snake_case", nil, nil, nil),
        ("UPPER_SNAKE_CASE", nil, nil, nil),
        ("_1", nil, nil, nil),
        ("_one_two_three_", nil, nil, nil),
        ("camelCased", nil, nil, nil),
        ("UpperCamelCase", nil, nil, nil),
        ("BEFORE2023", nil, nil, nil),

        // Escaped keywords
        ("associatedtype", nil, nil, nil),
        ("Protocol", nil, nil, nil),
      ],
      config: .mock(
        options: .init(conversionStrategies: .init(enumCases: .camelCase))
      )
    )

    let expected = """
    enum CasedEnum: String, EnumType {
      case lowercase = "lowercase"
      case uppercase = "UPPERCASE"
      case capitalized = "Capitalized"
      case snakeCase = "snake_case"
      case upperSnakeCase = "UPPER_SNAKE_CASE"
      case _1 = "_1"
      case _oneTwoThree_ = "_one_two_three_"
      case camelCased = "camelCased"
      case upperCamelCase = "UpperCamelCase"
      case before2023 = "BEFORE2023"
      case `associatedtype` = "associatedtype"
      case `protocol` = "Protocol"
    }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  func test_render_givenOption_caseConversionStrategy_default_generatesSwiftEnumValues_respectingSchemaValueCasing() throws {
    // given
    buildSubject(
      name: "casedEnum",
      values: [
        // Mixed case
        ("lowercase", nil, nil, nil),
        ("UPPERCASE", nil, nil, nil),
        ("Capitalized", nil, nil, nil),
        ("snake_case", nil, nil, nil),
        ("UPPER_SNAKE_CASE", nil, nil, nil),
        ("_1", nil, nil, nil),
        ("_one_two_three_", nil, nil, nil),
        ("camelCased", nil, nil, nil),
        ("UpperCamelCase", nil, nil, nil),
        ("BEFORE2023", nil, nil, nil),

        // Escaped keywords
        ("associatedtype", nil, nil, nil),
        ("Protocol", nil, nil, nil),
      ],
      config: .mock(
        options: .init(conversionStrategies: .init(enumCases: .none))
      )
    )

    let expected = """
    enum CasedEnum: String, EnumType {
      case lowercase
      case UPPERCASE
      case Capitalized
      case snake_case
      case UPPER_SNAKE_CASE
      case _1
      case _one_two_three_
      case camelCased
      case UpperCamelCase
      case BEFORE2023
      case `associatedtype`
      case `Protocol`
    }
    
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  // MARK: Deprecation Tests

  func test__render__givenOption_deprecatedInclude_warningsExclude_whenDeprecation_shouldGenerateEnumCase_withDeprecationComment() throws {
    // given / when
    buildSubject(
      values: [
        ("ONE", nil, nil, nil),
        ("TWO", "Deprecated for tests", nil, nil),
        ("THREE", nil, nil, nil)
      ],
      config: ApolloCodegenConfiguration.mock(options: .init(
        deprecatedEnumCases: .include,
        warningsOnDeprecatedUsage: .exclude
      ))
    )

    let expected = """
    enum TestEnum: String, EnumType {
      case one = "ONE"
      /// **Deprecated**: Deprecated for tests
      case two = "TWO"
      case three = "THREE"
    }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  func test__render__givenOption_deprecatedInclude_warningsInclude_whenDeprecation_shouldGenerateEnumCase_withDeprecationComment() throws {
    // given / when
    buildSubject(
      values: [
        ("ONE", nil, nil, nil),
        ("TWO", "Deprecated for tests", nil, nil),
        ("THREE", nil, nil, nil)
      ],
      config: ApolloCodegenConfiguration.mock(options: .init(
        deprecatedEnumCases: .include,
        warningsOnDeprecatedUsage: .include
      ))
    )

    let expected = """
    enum TestEnum: String, EnumType {
      case one = "ONE"
      /// **Deprecated**: Deprecated for tests
      case two = "TWO"
      case three = "THREE"
    }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  func test__render__givenOption_deprecatedExclude_warningsInclude_whenDeprecation_shouldNotGenerateEnumCase() throws {
    // given / when
    buildSubject(
      values: [
        ("ONE", "Deprecated for tests", nil, nil),
        ("TWO", nil, nil, nil),
        ("THREE", "Deprecated for tests", nil, nil)
      ],
      config: ApolloCodegenConfiguration.mock(options: .init(
        deprecatedEnumCases: .exclude,
        warningsOnDeprecatedUsage: .include
      ))
    )

    let expected = """
    enum TestEnum: String, EnumType {
      case two = "TWO"
    }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  func test__render__givenOption_deprecatedExclude_warningsExclude_whenDeprecation_shouldNotGenerateEnumCase() throws {
    // given / when
    buildSubject(
      values: [
        ("ONE", "Deprecated for tests", nil, nil),
        ("TWO", nil, nil, nil),
        ("THREE", "Deprecated for tests", nil, nil)
      ],
      config: ApolloCodegenConfiguration.mock(options: .init(
        deprecatedEnumCases: .exclude,
        warningsOnDeprecatedUsage: .exclude
      ))
    )

    let expected = """
    enum TestEnum: String, EnumType {
      case two = "TWO"
    }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  // MARK: Documentation Tests

  func test__render__givenSchemaDocumentation_include_hasDocumentation_shouldGenerateDocumentationComment() throws {
    // given
    let documentation = "This is some great documentation!"
    buildSubject(
      documentation: documentation,
      values: [
        ("ONE", "Deprecated for tests", "Doc: One", nil),
        ("TWO", nil, "Doc: Two", nil),
        ("THREE", "Deprecated for tests", nil, nil)
      ],
      config: ApolloCodegenConfiguration.mock(options: .init(
        deprecatedEnumCases: .include,
        schemaDocumentation: .include,
        warningsOnDeprecatedUsage: .include
      ))
    )

    let expected = """
    /// \(documentation)
    enum TestEnum: String, EnumType {
      /// Doc: One
      ///
      /// **Deprecated**: Deprecated for tests
      case one = "ONE"
      /// Doc: Two
      case two = "TWO"
      /// **Deprecated**: Deprecated for tests
      case three = "THREE"
    }

    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected))
  }

  func test__render__givenSchemaDocumentation_include_warningsOnDeprecation_exclude_hasDocumentation_shouldGenerateDocumentationComment() throws {
    // given
    let documentation = "This is some great documentation!"
    buildSubject(
      documentation: documentation,
      values: [
        ("ONE", "Deprecated for tests", "Doc: One", nil),
        ("TWO", nil, "Doc: Two", nil),
        ("THREE", "Deprecated for tests", nil, nil)
      ],
      config: ApolloCodegenConfiguration.mock(options: .init(
        deprecatedEnumCases: .include,
        schemaDocumentation: .include,
        warningsOnDeprecatedUsage: .exclude
      ))
    )

    let expected = """
    /// \(documentation)
    enum TestEnum: String, EnumType {
      /// Doc: One
      ///
      /// **Deprecated**: Deprecated for tests
      case one = "ONE"
      /// Doc: Two
      case two = "TWO"
      /// **Deprecated**: Deprecated for tests
      case three = "THREE"
    }

    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected))
  }

  func test__render__givenSchemaDocumentation_exclude_hasDocumentation_shouldNotGenerateDocumentationComment() throws {
    // given
    let documentation = "This is some great documentation!"
    buildSubject(
      documentation: documentation,
      values: [
        ("ONE", "Deprecated for tests", "Doc: One", nil),
        ("TWO", nil, "Doc: Two", nil),
        ("THREE", "Deprecated for tests", nil, nil)
      ],
      config: ApolloCodegenConfiguration.mock(options: .init(
        deprecatedEnumCases: .include,
        schemaDocumentation: .exclude,
        warningsOnDeprecatedUsage: .exclude
      ))
    )

    let expected = """
    enum TestEnum: String, EnumType {
      /// **Deprecated**: Deprecated for tests
      case one = "ONE"
      case two = "TWO"
      /// **Deprecated**: Deprecated for tests
      case three = "THREE"
    }
    
    """

    // when
    let rendered = renderSubject()

    // then
    expect(rendered).to(equalLineByLine(expected))
  }
  
  // MARK: - Reserved Keyword Tests
  
  func test_render_givenReservedKeywordType_AsEscapedType() {
    let keywords = ["Type", "type"]
    
    keywords.forEach { keyword in
      // given
      buildSubject(name: keyword)

      let expected = """
      enum \(keyword.firstUppercased)_Enum: String, EnumType {
      """

      // when
      let actual = renderSubject()

      // then
      expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    }
  }
  
  // MARK: - Schema Customization Tests
  
  func test__render__givenEnumAndValues_withCustomNames_shouldRenderWithCustomNames() throws {
    // given
    buildSubject(
      name: "MyEnum",
      customName: "MyCustomEnum",
      values: [
        // Mixed case
        ("caseOne", nil, nil, nil),
        ("myCase", nil, nil, "myCustomCase")
      ]
    )

    let expected = """
    // Renamed from GraphQL schema value: 'MyEnum'
    enum MyCustomEnum: String, EnumType {
      case caseOne = "caseOne"
      // Renamed from GraphQL schema value: 'myCase'
      case myCustomCase = "myCase"
    }
    
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }
  
}
