import Foundation

public struct StaticContextCollector: ContextCollecting {
    private let context: AppContext

    public init(context: AppContext) {
        self.context = context
    }

    public func currentContext() async throws -> AppContext {
        context
    }
}

public actor BufferingTextInserter: TextInserting {
    private(set) public var insertedTexts: [String] = []

    public init() {}

    public func insert(_ text: String, into context: AppContext) async throws {
        guard !context.isSecureInput else {
            throw LocalTypeError.secureInputBlocked(context.appName)
        }
        insertedTexts.append(text)
    }

    public func lastInsertedText() -> String? {
        insertedTexts.last
    }
}
