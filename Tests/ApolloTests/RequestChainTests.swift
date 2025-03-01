import XCTest
@testable import Apollo
import ApolloAPI
import ApolloInternalTestHelpers

class RequestChainTests: XCTestCase {

  func testEmptyInterceptorArrayReturnsCorrectError() {
    class TestProvider: InterceptorProvider {
      func interceptors<Operation: GraphQLOperation>(
        for operation: Operation
      ) -> [any ApolloInterceptor] {
        []
      }
    }

    let transport = RequestChainNetworkTransport(interceptorProvider: TestProvider(),
                                                 endpointURL: TestURL.mockServer.url)
    let expectation = self.expectation(description: "kickoff failed")
    _ = transport.send(operation: MockQuery.mock()) { result in
      defer {
        expectation.fulfill()
      }

      switch result {
      case .success:
        XCTFail("This should not have succeeded")
      case .failure(let error):
        switch error {
        case InterceptorRequestChain.ChainError.noInterceptors:
          // This is what we want.
          break
        default:
          XCTFail("Incorrect error for no interceptors: \(error)")
        }
      }
    }


    self.wait(for: [expectation], timeout: 1)
  }

  func testCancellingChainCallsCancelOnInterceptorsWhichImplementCancellableAndNotOnOnesThatDont() {
    class TestProvider: InterceptorProvider {
      let cancellationInterceptor = CancellationHandlingInterceptor()
      let retryInterceptor = BlindRetryingTestInterceptor()

      func interceptors<Operation: GraphQLOperation>(
        for operation: Operation
      ) -> [any ApolloInterceptor] {
        [
          self.cancellationInterceptor,
          self.retryInterceptor
        ]
      }
    }

    let provider = TestProvider()
    let transport = RequestChainNetworkTransport(interceptorProvider: provider,
                                                 endpointURL: TestURL.mockServer.url)
    let expectation = self.expectation(description: "Send succeeded")
    expectation.isInverted = true
    let cancellable = transport.send(operation: MockQuery.mock()) { _ in
      XCTFail("This should not have gone through")
      expectation.fulfill()
    }

    cancellable.cancel()
    XCTAssertTrue(provider.cancellationInterceptor.hasBeenCancelled)
    XCTAssertFalse(provider.retryInterceptor.hasBeenCancelled)
    self.wait(for: [expectation], timeout: 2)
  }

  func test__send__ErrorInterceptorGetsCalledAfterAnErrorIsReceived() {
    class ErrorInterceptor: ApolloErrorInterceptor {
      var error: (any Error)? = nil

      func handleErrorAsync<Operation: GraphQLOperation>(
        error: any Error,
          chain: any RequestChain,
          request: HTTPRequest<Operation>,
          response: HTTPResponse<Operation>?,
          completion: @escaping (Result<GraphQLResult<Operation.Data>, any Error>) -> Void) {

        self.error = error
        completion(.failure(error))
      }
    }

    class TestProvider: InterceptorProvider {
      let errorInterceptor = ErrorInterceptor()
      func interceptors<Operation: GraphQLOperation>(
        for operation: Operation
      ) -> [any ApolloInterceptor] {
        return [
          // An interceptor which will error without a response
          AutomaticPersistedQueryInterceptor()
        ]
      }

      func additionalErrorInterceptor<Operation: GraphQLOperation>(for operation: Operation) -> (any ApolloErrorInterceptor)? {
        return self.errorInterceptor
      }
    }

    let provider = TestProvider()
    let transport = RequestChainNetworkTransport(interceptorProvider: provider,
                                                 endpointURL: TestURL.mockServer.url,
                                                 autoPersistQueries: true)

    let expectation = self.expectation(description: "Hero name query complete")
    _ = transport.send(operation: MockQuery.mock()) { result in
      defer {
        expectation.fulfill()
      }
      switch result {
      case .success:
        XCTFail("This should not have succeeded")
      case .failure(let error):
        switch error {
        case AutomaticPersistedQueryInterceptor.APQError.noParsedResponse:
          // This is what we want.
          break
        default:
          XCTFail("Unexpected error: \(error)")
        }
      }
    }

    self.wait(for: [expectation], timeout: 1)

    switch provider.errorInterceptor.error {
    case .some(let error):
      switch error {
      case AutomaticPersistedQueryInterceptor.APQError.noParsedResponse:
        // Again, this is what we expect.
        break
      default:
        XCTFail("Unexpected error on the interceptor: \(error)")
      }
    case .none:
      XCTFail("Error interceptor did not receive an error!")
    }
  }

  func test__upload__ErrorInterceptorGetsCalledAfterAnErrorIsReceived() throws {
    class ErrorInterceptor: ApolloErrorInterceptor {
      var error: (any Error)? = nil

      func handleErrorAsync<Operation: GraphQLOperation>(
        error: any Error,
          chain: any RequestChain,
          request: HTTPRequest<Operation>,
          response: HTTPResponse<Operation>?,
          completion: @escaping (Result<GraphQLResult<Operation.Data>, any Error>) -> Void) {

        self.error = error
        completion(.failure(error))
      }
    }

    class TestProvider: InterceptorProvider {
      let errorInterceptor = ErrorInterceptor()
      func interceptors<Operation: GraphQLOperation>(
        for operation: Operation
      ) -> [any ApolloInterceptor] {
        return [
          // An interceptor which will error without a response
          ResponseCodeInterceptor()
        ]
      }

      func additionalErrorInterceptor<Operation: GraphQLOperation>(for operation: Operation) -> (any ApolloErrorInterceptor)? {
        return self.errorInterceptor
      }
    }

    let provider = TestProvider()
    let transport = RequestChainNetworkTransport(interceptorProvider: provider,
                                                 endpointURL: TestURL.mockServer.url,
                                                 autoPersistQueries: true)

    let fileURL = TestFileHelper.fileURLForFile(named: "a", extension: "txt")
    let file = try GraphQLFile(
      fieldName: "file",
      originalName: "a.txt",
      fileURL: fileURL
    )

    let expectation = self.expectation(description: "Hero name query complete")
    _ = transport.upload(operation: MockQuery.mock(), files: [file], context: nil) { result in
      defer {
        expectation.fulfill()
      }
      switch result {
      case .success:
        XCTFail("This should not have succeeded")
      case .failure(let error):
        switch error {
        case ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode:
          // This is what we want.
          break
        default:
          XCTFail("Unexpected error: \(error)")
        }
      }
    }

    self.wait(for: [expectation], timeout: 1)

    switch provider.errorInterceptor.error {
    case .some(let error):
      switch error {
      case ResponseCodeInterceptor.ResponseCodeError.invalidResponseCode:
        // Again, this is what we expect.
        break
      default:
        XCTFail("Unexpected error on the interceptor: \(error)")
      }
    case .none:
      XCTFail("Error interceptor did not receive an error!")
    }
  }

  func testErrorInterceptorGetsCalledInDefaultInterceptorProviderSubclass() {
    class ErrorInterceptor: ApolloErrorInterceptor {
      var error: (any Error)? = nil

      func handleErrorAsync<Operation: GraphQLOperation>(
        error: any Error,
        chain: any RequestChain,
        request: HTTPRequest<Operation>,
        response: HTTPResponse<Operation>?,
        completion: @escaping (Result<GraphQLResult<Operation.Data>, any Error>) -> Void) {

        self.error = error
        completion(.failure(error))
      }
    }

    class TestProvider: DefaultInterceptorProvider {
      let errorInterceptor = ErrorInterceptor()

      override func interceptors<Operation: GraphQLOperation>(
        for operation: Operation
      ) -> [any ApolloInterceptor] {
        return [
          // An interceptor which will error without a response
          AutomaticPersistedQueryInterceptor()
        ]
      }

      override func additionalErrorInterceptor<Operation: GraphQLOperation>(for operation: Operation) -> (any ApolloErrorInterceptor)? {
        return self.errorInterceptor
      }
    }

    let provider = TestProvider(store: ApolloStore())
    let transport = RequestChainNetworkTransport(interceptorProvider: provider,
                                                 endpointURL: TestURL.mockServer.url,
                                                 autoPersistQueries: true)

    let expectation = self.expectation(description: "Hero name query complete")
    _ = transport.send(operation: MockQuery.mock()) { result in
      defer {
        expectation.fulfill()
      }
      switch result {
      case .success:
        XCTFail("This should not have succeeded")
      case .failure(let error):
        switch error {
        case AutomaticPersistedQueryInterceptor.APQError.noParsedResponse:
          // This is what we want.
          break
        default:
          XCTFail("Unexpected error: \(error)")
        }
      }
    }

    self.wait(for: [expectation], timeout: 1)

    switch provider.errorInterceptor.error {
    case .some(let error):
      switch error {
      case AutomaticPersistedQueryInterceptor.APQError.noParsedResponse:
        // Again, this is what we expect.
        break
      default:
        XCTFail("Unexpected error on the interceptor: \(error)")
      }
    case .none:
      XCTFail("Error interceptor did not receive an error!")
    }
  }

  func test__error__givenGraphqlError_withoutData_shouldReturnError() {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      ),
      data: """
      {
        "errors": [{
          "message": "Bad request, could not start execution!"
        }]
      }
      """.data(using: .utf8)
    )

    let interceptorProvider = DefaultInterceptorProvider(client: client, store: ApolloStore())
    let interceptors = interceptorProvider.interceptors(for: MockQuery.mock())
    let requestChain = InterceptorRequestChain(interceptors: interceptors)

    let expectation = expectation(description: "Response received")

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version"
    )

    // when + then
    requestChain.kickoff(request: request) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        XCTAssertEqual(data.errors, [
          GraphQLError("Bad request, could not start execution!")
        ])
      case let .failure(error):
        XCTFail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: 1)
  }

  // MARK: Multipart request tests

  struct RequestTrapInterceptor: ApolloInterceptor {
    let callback: (URLRequest) -> (Void)

    public var id: String = UUID().uuidString

    init(_ callback: @escaping (URLRequest) -> (Void)) {
      self.callback = callback
    }

    func interceptAsync<Operation>(
      chain: any RequestChain,
      request: HTTPRequest<Operation>,
      response: HTTPResponse<Operation>?,
      completion: @escaping (Result<GraphQLResult<Operation.Data>, any Error>
    ) -> Void) {
      callback(try! request.toURLRequest())
    }
  }

  func test__request__givenSubscription_shouldAddMultipartAcceptHeader() {
    let expectation = self.expectation(description: "Request header verified")

    let interceptor = RequestTrapInterceptor { request in
      guard let header = request.allHTTPHeaderFields?["Accept"] else {
        XCTFail()
        return
      }

      XCTAssertEqual(header, "multipart/mixed;\(MultipartResponseSubscriptionParser.protocolSpec),application/graphql-response+json,application/json")
      expectation.fulfill()
    }

    let transport = RequestChainNetworkTransport(
      interceptorProvider: MockInterceptorProvider([interceptor]),
      endpointURL: TestURL.mockServer.url
    )

    _ = transport.send(operation: MockSubscription.mock()) { result in
      // noop
    }

    wait(for: [expectation], timeout: 1)
  }

  func test__request__givenSubscription_whenTransportInitializedWithAdditionalHeaders_shouldOverwriteOnlyAcceptHeader() {
    let expectation = self.expectation(description: "Request header verified")

    let interceptor = RequestTrapInterceptor { request in
      guard let header = request.allHTTPHeaderFields?["Accept"] else {
        XCTFail()
        return
      }

      XCTAssertEqual(header, "multipart/mixed;\(MultipartResponseSubscriptionParser.protocolSpec),application/graphql-response+json,application/json")
      XCTAssertNotNil(request.allHTTPHeaderFields?["Random"])
      expectation.fulfill()
    }

    let transport = RequestChainNetworkTransport(
      interceptorProvider: MockInterceptorProvider([interceptor]),
      endpointURL: TestURL.mockServer.url,
      additionalHeaders: [
        "Accept": "multipart/mixed",
        "Random": "still-here"
      ]
    )

    _ = transport.send(operation: MockSubscription.mock()) { result in
      // noop
    }

    wait(for: [expectation], timeout: 1)
  }

  func test__request__givenQuery_shouldAddMultipartAcceptHeader() {
    let expectation = self.expectation(description: "Request header verified")

    let interceptor = RequestTrapInterceptor { request in
      guard let header = request.allHTTPHeaderFields?["Accept"] else {
        XCTFail()
        return
      }

      XCTAssertEqual(header, "multipart/mixed;\(MultipartResponseDeferParser.protocolSpec),application/graphql-response+json,application/json")
      expectation.fulfill()
    }

    let transport = RequestChainNetworkTransport(
      interceptorProvider: MockInterceptorProvider([interceptor]),
      endpointURL: TestURL.mockServer.url
    )

    _ = transport.send(operation: MockQuery.mock()) { result in
      // noop
    }

    wait(for: [expectation], timeout: 1)
  }

  func test__request__givenMutation_shouldAddMultipartAcceptHeader() {
    let expectation = self.expectation(description: "Request header verified")

    let interceptor = RequestTrapInterceptor { request in
      guard let header = request.allHTTPHeaderFields?["Accept"] else {
        XCTFail()
        return
      }

      XCTAssertEqual(header, "multipart/mixed;\(MultipartResponseDeferParser.protocolSpec),application/graphql-response+json,application/json")
      expectation.fulfill()
    }

    let transport = RequestChainNetworkTransport(
      interceptorProvider: MockInterceptorProvider([interceptor]),
      endpointURL: TestURL.mockServer.url
    )

    _ = transport.send(operation: MockMutation.mock()) { result in
      // noop
    }

    wait(for: [expectation], timeout: 1)
  }

  func test__request__givenQuery_whenTransportInitializedWithAdditionalHeaders_shouldOverwriteOnlyAcceptHeader() {
    let expectation = self.expectation(description: "Request header verified")

    let interceptor = RequestTrapInterceptor { request in
      guard let header = request.allHTTPHeaderFields?["Accept"] else {
        XCTFail()
        return
      }

      XCTAssertEqual(header, "multipart/mixed;\(MultipartResponseDeferParser.protocolSpec),application/graphql-response+json,application/json")
      XCTAssertNotNil(request.allHTTPHeaderFields?["Random"])
      expectation.fulfill()
    }

    let transport = RequestChainNetworkTransport(
      interceptorProvider: MockInterceptorProvider([interceptor]),
      endpointURL: TestURL.mockServer.url,
      additionalHeaders: [
        "Accept": "multipart/mixed",
        "Random": "still-here"
      ]
    )

    _ = transport.send(operation: MockQuery.mock()) { result in
      // noop
    }

    wait(for: [expectation], timeout: 1)
  }

  func test__request__givenMutation_whenTransportInitializedWithAdditionalHeaders_shouldOverwriteOnlyAcceptHeader() {
    let expectation = self.expectation(description: "Request header verified")

    let interceptor = RequestTrapInterceptor { request in
      guard let header = request.allHTTPHeaderFields?["Accept"] else {
        XCTFail()
        return
      }

      XCTAssertEqual(header, "multipart/mixed;\(MultipartResponseDeferParser.protocolSpec),application/graphql-response+json,application/json")
      XCTAssertNotNil(request.allHTTPHeaderFields?["Random"])
      expectation.fulfill()
    }

    let transport = RequestChainNetworkTransport(
      interceptorProvider: MockInterceptorProvider([interceptor]),
      endpointURL: TestURL.mockServer.url,
      additionalHeaders: [
        "Accept": "multipart/mixed",
        "Random": "still-here"
      ]
    )

    _ = transport.send(operation: MockMutation.mock()) { result in
      // noop
    }

    wait(for: [expectation], timeout: 1)
  }

  // MARK: Memory tests

  private class Hero: MockSelectionSet {
    typealias Schema = MockSchemaMetadata

    override class var __selections: [Selection] {[
      .field("__typename", String.self),
      .field("name", String.self)
    ]}

    var name: String { __data["name"] }
  }

  struct DelayInterceptor: ApolloInterceptor {
    let seconds: Double

    public var id: String = UUID().uuidString

    init(_ seconds: Double) {
      self.seconds = seconds
    }

    func interceptAsync<Operation>(
      chain: any RequestChain,
      request: HTTPRequest<Operation>,
      response: HTTPResponse<Operation>?,
      completion: @escaping (Result<GraphQLResult<Operation.Data>, any Error>
    ) -> Void) {
      DispatchQueue.main.asyncAfter(wallDeadline: DispatchWallTime.now() + seconds) {
        chain.proceedAsync(
          request: request,
          response: response,
          interceptor: self,
          completion: completion
        )
      }
    }
  }

  func test__memory_management__givenQuery_whenCompleted_shouldNotHaveRetainCycle() throws {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      ),
      data: """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2"
        }
      }
      """.data(using: .utf8)
    )

    var requestChain: (any RequestChain)? = InterceptorRequestChain(interceptors: [
      NetworkFetchInterceptor(client: client),
      JSONResponseParsingInterceptor()
    ])
    weak var weakRequestChain: (any RequestChain)? = requestChain

    let expectedData = try Hero(data: [
      "__typename": "Hero",
      "name": "R2-D2"
    ], variables: nil)

    let expectation = expectation(description: "Response received")

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version"
    )

    // when
    requestChain?.kickoff(request: request) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        XCTAssertEqual(data.data, expectedData)
      case let .failure(error):
        XCTFail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: 1)

    // then
    XCTAssertNotNil(weakRequestChain)
    requestChain = nil
    XCTAssertNil(weakRequestChain)
  }

  func test__memory_management__givenSubscription_whenCancelled_shouldNotHaveRetainCycle() throws {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "multipart/mixed;boundary=graphql;subscriptionSpec=1.0"]
      ),
      data: """
      
      --graphql
      content-type: application/json

      {
        "payload": {
          "data": {
            "__typename": "Hero",
            "name": "R2-D2"
          }
        }
      }
      --graphql
      content-type: application/json

      {
        "payload": {
          "data": {
            "__typename": "Hero",
            "name": "R2-D2"
          }
        }
      }
      --graphql--
      """.crlfFormattedData()
    )

    var requestChain: (any RequestChain)? = InterceptorRequestChain(interceptors: [
      NetworkFetchInterceptor(client: client),
      MultipartResponseParsingInterceptor(),
      JSONResponseParsingInterceptor()
    ])
    weak var weakRequestChain: (any RequestChain)? = requestChain

    let expectedData = try Hero(data: [
      "__typename": "Hero",
      "name": "R2-D2"
    ], variables: nil)

    let expectation = expectation(description: "Response received")
    expectation.expectedFulfillmentCount = 2

    let request = JSONRequest(
      operation: MockSubscription<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version"
    )

    // when
    requestChain?.kickoff(request: request) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        XCTAssertEqual(data.data, expectedData)
      case let .failure(error):
        XCTFail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: 1)

    // then
    XCTAssertNotNil(weakRequestChain)
    requestChain?.cancel()
    requestChain = nil
    XCTAssertNil(weakRequestChain)
  }

  func test__memory_management__givenQuery_whenCancelled_shouldNotCrash() throws {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      ),
      data: """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2"
        }
      }
      """.data(using: .utf8)
    )

    let provider = MockInterceptorProvider([
      DelayInterceptor(0.5),
      NetworkFetchInterceptor(client: client),
      JSONResponseParsingInterceptor()
    ])

    let transport = RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )

    let expectation = expectation(description: "Response received")
    expectation.isInverted = true
    
    let cancellable = transport.send(operation: MockQuery<Hero>()) { result in
      XCTFail("Unexpected response: \(result)")

      expectation.fulfill()
    }

    DispatchQueue.main.async {
      cancellable.cancel()
    }

    wait(for: [expectation], timeout: 1)
  }

  func test__memory_management__givenQuery_whenCancelledAfterInterceptorChainFinished_shouldNotCrash() throws {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      ),
      data: """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2"
        }
      }
      """.data(using: .utf8)
    )

    let provider = MockInterceptorProvider([
      NetworkFetchInterceptor(client: client),
      JSONResponseParsingInterceptor()
    ])
    let transport = RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )

    let expectedData = try Hero(data: [
      "__typename": "Hero",
      "name": "R2-D2"
    ], variables: nil)

    let expectation = expectation(description: "Response received")

    let cancellable = transport.send(operation: MockQuery<Hero>()) { result in
      defer {
        expectation.fulfill()
      }

      switch result {
      case let .success(data):
        XCTAssertEqual(data.data, expectedData)
      case let .failure(error):
        XCTFail("Unexpected failure result: \(error)")
      }
    }

    wait(for: [expectation], timeout: 1)

    DispatchQueue.main.async {
      cancellable.cancel()
    }
  }

  func test__memory_management__givenOperation_withEarlyInterceptorChainExit_success_shouldNotHaveRetainCycle() throws {
    // given
    let store = ApolloStore(cache: InMemoryNormalizedCache(records: [
      "QUERY_ROOT": [
        "__typename": "Hero",
        "name": "R2-D2"
      ]
    ]))

    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      ),
      data: nil
    )

    var requestChain: (any RequestChain)? = InterceptorRequestChain(interceptors: [
      CacheReadInterceptor(store: store),
      NetworkFetchInterceptor(client: client),
      JSONResponseParsingInterceptor()
    ])
    weak var weakRequestChain: (any RequestChain)? = requestChain

    let expectedData = try Hero(data: [
      "__typename": "Hero",
      "name": "R2-D2"
    ], variables: nil)

    let expectation = expectation(description: "Response received")

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version",
      cachePolicy: .returnCacheDataDontFetch // early exit achieved by only wanting cache data
    )

    // when
    requestChain?.kickoff(request: request) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        XCTAssertEqual(data.data, expectedData)
      case let .failure(error):
        XCTFail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: 1)

    // then
    XCTAssertNotNil(weakRequestChain)
    requestChain = nil
    XCTAssertNil(weakRequestChain)
  }

  func test__memory_management__givenOperation_withEarlyInterceptorChainExit_failure_shouldNotHaveRetainCycle() throws {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      ),
      data: nil
    )

    var requestChain: (any RequestChain)? = InterceptorRequestChain(interceptors: [
      CacheReadInterceptor(store: ApolloStore()),
      NetworkFetchInterceptor(client: client),
      JSONResponseParsingInterceptor()
    ])

    weak var weakRequestChain: (any RequestChain)? = requestChain

    let expectation = expectation(description: "Response received")

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version",
      cachePolicy: .returnCacheDataDontFetch // early exit achieved by only wanting cache data
    )

    // when
    requestChain?.kickoff(request: request) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        XCTFail("Unexpected success result - \(data)")
      case .failure:
        break
      }
    }

    wait(for: [expectation], timeout: 1)

    // then
    XCTAssertNotNil(weakRequestChain)
    requestChain = nil
    XCTAssertNil(weakRequestChain)
  }

  func test__memory_management__givenOperation_withEarlyAndFinalInterceptorChainExit_shouldNotHaveRetainCycle_andShouldNotCrash() throws {
    throw XCTSkip("Flaky test skipped in PR #386- must be refactored or fixed in a separate PR.")

    // given
    let store = ApolloStore(cache: InMemoryNormalizedCache(records: [
      "QUERY_ROOT": [
        "__typename": "Hero",
        "name": "R2-D2"
      ]
    ]))

    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      ),
      data: """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2"
        }
      }
      """.data(using: .utf8)
    )

    var requestChain: (any RequestChain)? = InterceptorRequestChain(interceptors: [
      CacheReadInterceptor(store: store),
      NetworkFetchInterceptor(client: client),
      JSONResponseParsingInterceptor()
    ])
    weak var weakRequestChain: (any RequestChain)? = requestChain

    let expectedData = try Hero(data: [
      "__typename": "Hero",
      "name": "R2-D2"
    ], variables: nil)

    let expectation = expectation(description: "Response received")
    expectation.expectedFulfillmentCount = 2

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version",
      cachePolicy: .returnCacheDataAndFetch // early return achieved by wanting cache data too
    )

    // when
    requestChain?.kickoff(request: request) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        XCTAssertEqual(data.data, expectedData)
      case let .failure(error):
        XCTFail("Unexpected failure result - \(error)")
      }
    }

    wait(for: [expectation], timeout: 1)

    // then
    XCTAssertNotNil(weakRequestChain)
    requestChain = nil
    XCTAssertNil(weakRequestChain)
  }

  func test__memory_management__givenOperation_whenRetryInterceptorChain_shouldNotHaveRetainCycle_andShouldNotCrash() throws {
    // given
    let store = ApolloStore()

    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      ),
      data: nil
    )

    var requestChain: (any RequestChain)? = InterceptorRequestChain(interceptors: [
      CacheReadInterceptor(store: store),
      NetworkFetchInterceptor(client: client),
      JSONResponseParsingInterceptor()
    ])

    weak var weakRequestChain: (any RequestChain)? = requestChain

    let expectation = expectation(description: "Response received")
    expectation.expectedFulfillmentCount = 2

    let expectedData = try Hero(data: [
      "__typename": "Hero",
      "name": "Han Solo"
    ], variables: nil)

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version",
      cachePolicy: .returnCacheDataDontFetch // early exit achieved by only wanting cache data
    )

    // when
    requestChain?.kickoff(request: request) { result in
      defer {
        expectation.fulfill()
      }

      switch (result) {
      case let .success(data):
        XCTFail("Unexpected success result - \(data)")
      case .failure:
        store.publish(records: [
          "QUERY_ROOT": [
            "__typename": "Hero",
            "name": "Han Solo"
          ]
        ])

        requestChain?.retry(request: request) { result in
          defer {
            expectation.fulfill()
          }

          switch result {
          case let .success(data):
            XCTAssertEqual(data.data, expectedData)
          case let .failure(error):
            XCTFail("Unexpected failure result - \(error)")
          }
        }
        break
      }
    }

    wait(for: [expectation], timeout: 2)

    // then
    XCTAssertNotNil(weakRequestChain)
    requestChain = nil
    XCTAssertNil(weakRequestChain)
  }

  // MARK: `proceedAsync` Tests

  @available(*, deprecated)
  struct SimpleForwardingInterceptor_deprecated: ApolloInterceptor {
    var id: String = UUID().uuidString

    let expectation: XCTestExpectation

    func interceptAsync<Operation>(
      chain: any Apollo.RequestChain,
      request: Apollo.HTTPRequest<Operation>,
      response: Apollo.HTTPResponse<Operation>?,
      completion: @escaping (Result<Apollo.GraphQLResult<Operation.Data>, any Error>) -> Void
    ) {
      expectation.fulfill()

      chain.proceedAsync(request: request, response: response, completion: completion)
    }
  }

  struct SimpleForwardingInterceptor: ApolloInterceptor {
    var id: String = UUID().uuidString

    let expectation: XCTestExpectation

    func interceptAsync<Operation>(
      chain: any Apollo.RequestChain,
      request: Apollo.HTTPRequest<Operation>,
      response: Apollo.HTTPResponse<Operation>?,
      completion: @escaping (Result<Apollo.GraphQLResult<Operation.Data>, any Error>) -> Void
    ) {
      expectation.fulfill()

      chain.proceedAsync(
        request: request,
        response: response,
        interceptor: self,
        completion: completion
      )
    }
  }

  @available(*, deprecated, message: "Testing deprecated function")
  func test__proceedAsync__givenInterceptors_usingDeprecatedFunction_shouldCallAllInterceptors() throws {
    let expectations = [
      expectation(description: "Interceptor 1 executed"),
      expectation(description: "Interceptor 2 executed"),
      expectation(description: "Interceptor 3 executed")
    ]

    let requestChain = InterceptorRequestChain(interceptors: [
      SimpleForwardingInterceptor_deprecated(expectation: expectations[0]),
      SimpleForwardingInterceptor_deprecated(expectation: expectations[1]),
      SimpleForwardingInterceptor_deprecated(expectation: expectations[2])
    ])

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version"
    )

    // when
    requestChain.kickoff(request: request) { result in }

    // then
    wait(for: expectations, timeout: 1, enforceOrder: true)
  }

  func test__proceedAsync__givenInterceptors_usingNewFunction_shouldCallAllInterceptors() throws {
    let expectations = [
      expectation(description: "Interceptor 1 executed"),
      expectation(description: "Interceptor 2 executed"),
      expectation(description: "Interceptor 3 executed")
    ]

    let requestChain = InterceptorRequestChain(interceptors: [
      SimpleForwardingInterceptor(expectation: expectations[0]),
      SimpleForwardingInterceptor(expectation: expectations[1]),
      SimpleForwardingInterceptor(expectation: expectations[2])
    ])

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version"
    )

    // when
    requestChain.kickoff(request: request) { result in }

    // then
    wait(for: expectations, timeout: 1, enforceOrder: true)
  }

  @available(*, deprecated, message: "Testing deprecated function")
  func test__proceedAsync__givenInterceptors_usingBothFunctions_shouldCallAllInterceptors() throws {
    let expectations = [
      expectation(description: "Interceptor 1 executed"),
      expectation(description: "Interceptor 2 executed"),
      expectation(description: "Interceptor 3 executed"),
      expectation(description: "Interceptor 4 executed"),
      expectation(description: "Interceptor 5 executed"),
      expectation(description: "Interceptor 6 executed"),
      expectation(description: "Interceptor 7 executed"),
      expectation(description: "Interceptor 8 executed")
    ]

    let requestChain = InterceptorRequestChain(interceptors: [
      SimpleForwardingInterceptor(expectation: expectations[0]),
      SimpleForwardingInterceptor_deprecated(expectation: expectations[1]),
      SimpleForwardingInterceptor(expectation: expectations[2]),
      SimpleForwardingInterceptor_deprecated(expectation: expectations[3]),
      SimpleForwardingInterceptor_deprecated(expectation: expectations[4]),
      SimpleForwardingInterceptor(expectation: expectations[5]),
      SimpleForwardingInterceptor(expectation: expectations[6]),
      SimpleForwardingInterceptor_deprecated(expectation: expectations[7])
    ])

    let request = JSONRequest(
      operation: MockQuery<Hero>(),
      graphQLEndpoint: TestURL.mockServer.url,
      clientName: "test-client",
      clientVersion: "test-client-version"
    )

    // when
    requestChain.kickoff(request: request) { result in }

    // then
    wait(for: expectations, timeout: 1, enforceOrder: true)
  }

  // MARK: Response Tests

  func test__response__givenUnsuccessfulStatusCode_shouldFail() throws {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 500,
        httpVersion: nil,
        headerFields: nil
      ),
      data: """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2"
        }
      }
      """.data(using: .utf8)
    )

    let provider = DefaultInterceptorProvider(
      client: client,
      store: ApolloStore()
    )

    let transport = RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )

    let expectation = expectation(description: "Response received")

    _ = transport.send(operation: MockQuery<Hero>()) { result in
      switch result {
      case .success:
        XCTFail("Unexpected response: \(result)")

      case .failure:
        expectation.fulfill()
      }
    }

    wait(for: [expectation], timeout: 1)
  }

  // This test is odd because you might assume it would fail but there is no content-type checking on standard
  // GraphQL response parsing. So this test is here to ensure that existing behaviour does not change.
  func test__response__givenUnknownContentType_shouldNotFail() throws {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["content-type": "unknown/type"]
      ),
      data: """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2"
        }
      }
      """.data(using: .utf8)
    )

    let provider = DefaultInterceptorProvider(
      client: client,
      store: ApolloStore()
    )

    let transport = RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )

    let expectation = expectation(description: "Response received")

    _ = transport.send(operation: MockQuery<Hero>()) { result in
      switch result {
      case let .success(responseData):
        XCTAssertEqual(responseData.data?.__typename, "Hero")
        XCTAssertEqual(responseData.data?.name, "R2-D2")

        expectation.fulfill()

      case .failure:
        XCTFail("Unexpected response: \(result)")
      }
    }

    wait(for: [expectation], timeout: 1)
  }

  func test__response__givenJSONContentType_shouldSucceed() throws {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["content-type": "application/json"]
      ),
      data: """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2"
        }
      }
      """.data(using: .utf8)
    )

    let provider = DefaultInterceptorProvider(
      client: client,
      store: ApolloStore()
    )

    let transport = RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )

    let expectation = expectation(description: "Response received")

    _ = transport.send(operation: MockQuery<Hero>()) { result in
      switch result {
      case let .success(responseData):
        XCTAssertEqual(responseData.data?.__typename, "Hero")
        XCTAssertEqual(responseData.data?.name, "R2-D2")

        expectation.fulfill()

      case .failure:
        XCTFail("Unexpected response: \(result)")
      }
    }

    wait(for: [expectation], timeout: 1)
  }

  func test__response__givenGraphQLOverHTTPContentType_shouldSucceed() throws {
    // given
    let client = MockURLSessionClient(
      response: .mock(
        url: TestURL.mockServer.url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["content-type": "application/graphql-response+json"]
      ),
      data: """
      {
        "data": {
          "__typename": "Hero",
          "name": "R2-D2"
        }
      }
      """.data(using: .utf8)
    )

    let provider = DefaultInterceptorProvider(
      client: client,
      store: ApolloStore()
    )

    let transport = RequestChainNetworkTransport(
      interceptorProvider: provider,
      endpointURL: TestURL.mockServer.url
    )

    let expectation = expectation(description: "Response received")

    _ = transport.send(operation: MockQuery<Hero>()) { result in
      switch result {
      case let .success(responseData):
        XCTAssertEqual(responseData.data?.__typename, "Hero")
        XCTAssertEqual(responseData.data?.name, "R2-D2")

        expectation.fulfill()

      case .failure:
        XCTFail("Unexpected response: \(result)")
      }
    }

    wait(for: [expectation], timeout: 1)
  }
}
