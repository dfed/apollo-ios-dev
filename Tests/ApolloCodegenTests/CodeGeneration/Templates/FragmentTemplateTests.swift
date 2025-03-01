import XCTest
import Nimble
@testable import ApolloCodegenLib
import IR
import ApolloCodegenInternalTestHelpers

class FragmentTemplateTests: XCTestCase {

  var schemaSDL: String!
  var document: String!
  var ir: IRBuilder!
  var fragment: IR.NamedFragment!
  var subject: FragmentTemplate!

  override func setUp() {
    super.setUp()
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
    }
    """

    document = """
    fragment TestFragment on Query {
      allAnimals {
        species
      }
    }
    """
  }

  override func tearDown() {
    schemaSDL = nil
    document = nil
    ir = nil
    fragment = nil
    subject = nil
    super.tearDown()
  }

  // MARK: - Helpers

  private func buildSubjectAndFragment(
    named fragmentName: String = "TestFragment",
    config: ApolloCodegenConfiguration = .mock()
  ) async throws {
    ir = try await .mock(schema: schemaSDL, document: document)
    let fragmentDefinition = try XCTUnwrap(ir.compilationResult[fragment: fragmentName])
    fragment = await ir.build(fragment: fragmentDefinition)
    subject = FragmentTemplate(
      fragment: fragment,
      config: ApolloCodegen.ConfigurationContext(config: config)
    )
  }

  private func renderSubject() -> String {
    subject.renderBodyTemplate(nonFatalErrorRecorder: .init()).description
  }

  // MARK: - Target Configuration Tests

  func test__target__givenModuleImports_targetHasModuleImports() async throws {
    // given
    document = """
    fragment TestFragment on Query @import(module: "ModuleA") {
      allAnimals {
        species
      }
    }
    """

    // when
    try await buildSubjectAndFragment()

    guard case let .operationFile(actual) = subject.target else {
      fail("expected operationFile target")
      return
    }

    // then
    expect(actual).to(equal(["ModuleA"]))
  }

  // MARK: Fragment Definition

  func test__render__givenFragment_generatesFragmentDeclarationDefinitionAndBoilerplate() async throws {
    // given
    let expected =
    """
    struct TestFragment: TestSchema.SelectionSet, Fragment {
      static var fragmentDefinition: StaticString {
        #"fragment TestFragment on Query { __typename allAnimals { __typename species } }"#
      }

      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }
    """

    // when
    try await buildSubjectAndFragment()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    expect(String(actual.reversed())).to(equalLineByLine("\n}", ignoringExtraLines: true))
  }
  
  func test__render__givenFragment_generatesFragmentDeclarationWithoutDefinition() async throws {
    // given
    let expected =
    """
    struct TestFragment: TestSchema.SelectionSet, Fragment {
      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }
    """

    // when
    try await buildSubjectAndFragment(config: .mock(
      options: .init(
        operationDocumentFormat: .operationId
      )
    ))

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    expect(String(actual.reversed())).to(equalLineByLine("\n}", ignoringExtraLines: true))
  }

  func test__render__givenLowercaseFragment_generatesTitleCaseTypeName() async throws {
    // given
    document = """
    fragment testFragment on Query {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
    struct TestFragment: TestSchema.SelectionSet, Fragment {
      static var fragmentDefinition: StaticString {
        #"fragment testFragment on Query { __typename allAnimals { __typename species } }"#
    """

    // when
    try await buildSubjectAndFragment(named: "testFragment")

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenFragmentWithUnderscoreInName_rendersDeclarationWithName() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }
    """

    document = """
    fragment Test_Fragment on Animal {
      species
    }
    """

    let expected = """
    struct Test_Fragment: TestSchema.SelectionSet, Fragment {
    """

    // when
    try await buildSubjectAndFragment(named: "Test_Fragment")
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render_parentType__givenFragmentTypeConditionAs_Object_rendersParentType() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Animal {
      species: String!
    }
    """

    document = """
    fragment TestFragment on Animal {
      species
    }
    """

    let expected = """
      static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Animal }
    """

    // when
    try await buildSubjectAndFragment()
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

  func test__render_parentType__givenFragmentTypeConditionAs_Interface_rendersParentType() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    interface Animal {
      species: String!
    }
    """

    document = """
    fragment TestFragment on Animal {
      species
    }
    """

    let expected = """
      static var __parentType: any ApolloAPI.ParentType { TestSchema.Interfaces.Animal }
    """

    // when
    try await buildSubjectAndFragment()
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

  func test__render_parentType__givenFragmentTypeConditionAs_Union_rendersParentType() async throws {
    // given
    schemaSDL = """
    type Query {
      allAnimals: [Animal!]
    }

    type Dog {
      species: String!
    }

    union Animal = Dog
    """

    document = """
    fragment TestFragment on Animal {
      ... on Dog {
        species
      }
    }
    """

    let expected = """
      static var __parentType: any ApolloAPI.ParentType { TestSchema.Unions.Animal }
    """

    // when
    try await buildSubjectAndFragment()
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 9, ignoringExtraLines: true))
  }

  func test__render__givenFragmentOnRootOperationTypeWithOnlyTypenameField_generatesFragmentDefinition_withNoSelections() async throws {
    // given
    document = """
    fragment TestFragment on Query {
      __typename
    }
    """

    try await buildSubjectAndFragment()

    let expected = """
    struct TestFragment: TestSchema.SelectionSet, Fragment {
      static var fragmentDefinition: StaticString {
        #"fragment TestFragment on Query { __typename }"#
      }

      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Query }
    }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  func test__render__givenFragmentWithOnlyTypenameField_generatesFragmentDefinition_withTypeNameSelection() async throws {
    // given
    document = """
    fragment TestFragment on Animal {
      __typename
    }
    """

    try await buildSubjectAndFragment()

    let expected = """
    struct TestFragment: TestSchema.SelectionSet, Fragment {
      static var fragmentDefinition: StaticString {
        #"fragment TestFragment on Animal { __typename }"#
      }

      let __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Animal }
      static var __selections: [ApolloAPI.Selection] { [
        .field("__typename", String.self),
      ] }
    }

    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected))
  }

  // MARK: Access Level Tests

  func test__render__givenModuleType_swiftPackageManager_generatesFragmentDefinition_withPublicAccess() async throws {
    // given
    try await buildSubjectAndFragment(config: .mock(.swiftPackage()))

    let expected = """
    public struct TestFragment: TestSchema.SelectionSet, Fragment {
      public static var fragmentDefinition: StaticString {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenModuleType_other_generatesFragmentDefinition_withPublicAccess() async throws {
    // given
    try await buildSubjectAndFragment(config: .mock(.other))

    let expected = """
    public struct TestFragment: TestSchema.SelectionSet, Fragment {
      public static var fragmentDefinition: StaticString {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenModuleType_embeddedInTarget_withInternalAccessModifier_generatesFragmentDefinition_withInternalAccess() async throws {
    // given
    try await buildSubjectAndFragment(
      config: .mock(.embeddedInTarget(name: "TestTarget", accessModifier: .internal))
    )

    let expected = """
    struct TestFragment: TestSchema.SelectionSet, Fragment {
      static var fragmentDefinition: StaticString {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__render__givenModuleType_embeddedInTarget_withPublicAccessModifier_generatesFragmentDefinition_withPublicAccess() async throws {
    // given
    try await buildSubjectAndFragment(
      config: .mock(.embeddedInTarget(name: "TestTarget", accessModifier: .public))
    )

    let expected = """
    struct TestFragment: TestSchema.SelectionSet, Fragment {
      public static var fragmentDefinition: StaticString {
    """

    // when
    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  // MARK: Initializer Tests

  func test__render_givenInitializerConfigIncludesNamedFragments_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    document = """
      fragment TestFragment on Animal {
        species
      }
      """

    let expected =
      """
        init(
          species: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "species": species,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestFragment.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndFragment(
      config: .mock(options: .init(
        selectionSetInitializers: [.namedFragments]
      )))

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragment_configIncludesSpecificFragment_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    document = """
      fragment TestFragment on Animal {
        species
      }
      """

    let expected =
      """
        init(
          species: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "species": species,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestFragment.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndFragment(
      config: .mock(options: .init(
        selectionSetInitializers: [.fragment(named: "TestFragment")]
      )))

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 17, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragment_configDoesNotIncludeNamedFragments_doesNotRenderInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    document = """
      fragment TestFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectAndFragment(
      config: .mock(options: .init(
        selectionSetInitializers: [.operations]
      )))

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine("}", atLine: 16, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragments_configIncludeSpecificFragmentWithOtherName_doesNotRenderInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    document = """
      fragment TestFragment on Animal {
        species
      }
      """

    // when
    try await buildSubjectAndFragment(
      config: .mock(options: .init(
        selectionSetInitializers: [.fragment(named: "OtherFragment")]
      )))

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine("}", atLine: 16, ignoringExtraLines: true))
  }

  func test__render_givenNamedFragments_asLocalCacheMutation_rendersInitializer() async throws {
    // given
    schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

    document = """
      fragment TestFragment on Animal @apollo_client_ios_localCacheMutation {
        species
      }
      """

    let expected =
      """
        init(
          species: String
        ) {
          self.init(_dataDict: DataDict(
            data: [
              "__typename": TestSchema.Objects.Animal.typename,
              "species": species,
            ],
            fulfilledFragments: [
              ObjectIdentifier(TestFragment.self)
            ]
          ))
        }
      """

    // when
    try await buildSubjectAndFragment(
      config: .mock(options: .init(
        selectionSetInitializers: []
      )))

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 20, ignoringExtraLines: true))
  }

  func test__render_givenOperationSelectionSet_initializerConfig_all_fieldMergingConfig_notAll_doesNotRenderInitializer() async throws {
    let tests: [ApolloCodegenConfiguration.FieldMerging] = [
      .none,
      .ancestors,
      .namedFragments,
      .siblings,
      [.ancestors, .namedFragments],
      [.siblings, .ancestors],
      [.siblings, .namedFragments]
    ]

    for test in tests {
      // given
      schemaSDL = """
      type Query {
        allAnimals: [Animal!]
      }

      type Animal {
        species: String!
      }
      """

      document = """
      fragment TestFragment on Animal {
        species
      }
      """

      // when
      try await buildSubjectAndFragment(config: .mock(
        options: .init(
          selectionSetInitializers: [.all]
        ),
        experimentalFeatures: .init(fieldMerging: test)
      ))

      let actual = renderSubject()

      // then
      expect(actual).to(equalLineByLine("}", atLine: 16, ignoringExtraLines: true))
    }
  }

  // MARK: Local Cache Mutation Tests
  func test__render__givenFragment__asLocalCacheMutation_generatesFragmentDeclarationDefinitionAsMutableSelectionSetAndBoilerplate() async throws {
    // given
    document = """
    fragment TestFragment on Query @apollo_client_ios_localCacheMutation {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
    struct TestFragment: TestSchema.MutableSelectionSet, Fragment {
    """

    // when
    try await buildSubjectAndFragment()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    expect(String(actual.reversed())).to(equalLineByLine("\n}", ignoringExtraLines: true))
  }

  func test__render__givenFragment__asLocalCacheMutation_generatesFragmentDefinitionStrippingLocalCacheMutationDirective() async throws {
    // given
    document = """
    fragment TestFragment on Query @apollo_client_ios_localCacheMutation {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
    struct TestFragment: TestSchema.MutableSelectionSet, Fragment {
      static var fragmentDefinition: StaticString {
        #"fragment TestFragment on Query { __typename allAnimals { __typename species } }"#
      }
    """

    // when
    try await buildSubjectAndFragment()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    expect(String(actual.reversed())).to(equalLineByLine("\n}", ignoringExtraLines: true))
  }

  func test__render__givenFragment__asLocalCacheMutation_generatesFragmentDefinitionAsMutableSelectionSet() async throws {
    // given
    document = """
    fragment TestFragment on Query @apollo_client_ios_localCacheMutation {
      allAnimals {
        species
      }
    }
    """

    let expected =
    """
      var __data: DataDict
      init(_dataDict: DataDict) { __data = _dataDict }

      static var __parentType: any ApolloAPI.ParentType { TestSchema.Objects.Query }
      static var __selections: [ApolloAPI.Selection] { [
        .field("allAnimals", [AllAnimal]?.self),
      ] }

      var allAnimals: [AllAnimal]? {
        get { __data["allAnimals"] }
        set { __data["allAnimals"] = newValue }
      }
    """

    // when
    try await buildSubjectAndFragment()

    let actual = renderSubject()

    // then
    expect(actual).to(equalLineByLine(expected, atLine: 6, ignoringExtraLines: true))
  }

  // MARK: Casing

  func test__casing__givenLowercasedSchemaName_generatesWithFirstUppercasedNamespace() async throws {
    // given
    try await buildSubjectAndFragment(config: .mock(schemaNamespace: "mySchema"))

    // then
    let expected = """
      struct TestFragment: MySchema.SelectionSet, Fragment {
      """

    let actual = renderSubject()

    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__casing__givenUppercasedSchemaName_generatesWithUppercasedNamespace() async throws {
    // given
    try await buildSubjectAndFragment(config: .mock(schemaNamespace: "MY_SCHEMA"))

    // then
    let expected = """
      struct TestFragment: MY_SCHEMA.SelectionSet, Fragment {
      """

    let actual = renderSubject()

    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }

  func test__casing__givenCapitalizedSchemaName_generatesWithCapitalizedNamespace() async throws {
    // given
    try await buildSubjectAndFragment(config: .mock(schemaNamespace: "MySchema"))

    // then
    let expected = """
      struct TestFragment: MySchema.SelectionSet, Fragment {
      """

    let actual = renderSubject()

    expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
  }
  
  // MARK: - Reserved Keyword Tests
  
  func test__render__givenFragmentReservedKeywordName_rendersEscapedName() async throws {
    let keywords = ["Type", "type"]
    
    try await keywords.asyncForEach { keyword in
      // given
      schemaSDL = """
      type Query {
        getUser(id: String): User
      }

      type User {
        id: String!
        name: String!
      }
      """

      document = """
      fragment \(keyword) on User {
          name
      }
      """

      let expected = """
      struct \(keyword.firstUppercased)_Fragment: TestSchema.SelectionSet, Fragment {
      """

      // when
      try await buildSubjectAndFragment(named: keyword)
      let actual = renderSubject()

      // then
      expect(actual).to(equalLineByLine(expected, ignoringExtraLines: true))
    }
  }
  
}
