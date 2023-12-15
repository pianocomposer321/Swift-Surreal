import Foundation
import WebSocketKit
import NIO

struct QueryId: Decodable {
  let id: Int
}

struct Person: Codable {
  let name: String
  let id: String
}

struct UnresolvedQuery {
  private let data: EventLoopPromise<String>
  private let jsonDecoder = JSONDecoder()

  init(data: EventLoopPromise<String>) {
    self.data = data
  }

  func succeed(_ value: String) {
    self.data.succeed(value)
  }

  private func getItems(json: Any?) throws -> [[String: Any]]? {
    if let dict = json as? [String: Any] {
      if let list = dict["result"] as? [[String: Any]] {
        if let results = list[0]["result"] as? [[String: Any]] {
          return results
        }
      }
    }

    return nil
  }

  func resolve<T: Decodable>() async throws -> [T]? {
    let resolvedData = try await self.data.futureResult.get()
    let json = try? JSONSerialization.jsonObject(with: resolvedData.data(using: .utf8)!, options: [])
    var resolved_items: [T] = []

    if let items = try getItems(json: json) {
      for item in items {
        let resolved = try? jsonDecoder.decode(T.self, from: JSONSerialization.data(withJSONObject: item))
        if let resolved = resolved {
          resolved_items.append(resolved)
        } else {
          return nil
        }
      }
    }

    return resolved_items
  }

  func resolveFirst<T: Decodable>() async throws -> T? {
    let resolvedData = try await self.data.futureResult.get()
    let json = try? JSONSerialization.jsonObject(with: resolvedData.data(using: .utf8)!, options: [])

    if let items = try getItems(json: json) {
      let resolved = try? jsonDecoder.decode(T.self, from: JSONSerialization.data(withJSONObject: items[0]))
      if let resolved = resolved {
        return resolved
      }
    }

    return nil
  }
}

class DbConn {
  private var unresolvedQueries = [Int: UnresolvedQuery]()
  private var nextId = 0
  private let wsPromise: EventLoopPromise<WebSocket>
  private lazy var ws: WebSocket = {
    return try! self.wsPromise.futureResult.wait()
  }()
  private let elg: EventLoopGroup

  init(elg: EventLoopGroup) {
    let wsPromise = elg.any().makePromise(of: WebSocket.self)

    self.elg = elg
    self.wsPromise = wsPromise
  }

  func connect() async throws {
    let decoder = JSONDecoder()
    try await WebSocket.connect(to: "ws://localhost:8000/rpc", on: elg) { ws in
      ws.send("""
      {
        "id": 0,
        "method": "use",
        "params": ["test", "test"]
      }
      """)

      ws.onText {ws, data in
        guard let queryRes = try? decoder.decode(QueryId.self, from: data.data(using: .utf8)!) else {
          print("Error: could not decode json response as QueryId")
          return
        }
        if queryRes.id == 0 {
          return
        }

        self.unresolvedQueries[queryRes.id]?.succeed(data)
      }

      self.wsPromise.succeed(ws)
    }.get()
  }

  private func getId() -> Int {
    self.nextId += 1
    return nextId
  }

  func query<T: Decodable>(as: T.Type, _ q: String) async throws -> [T]? {
    let id = self.getId()
    let promise = self.elg.any().makePromise(of: String.self)

    let _ = try await self.ws.send("""
    {
      "id": \(id),
      "method": "query",
      "params": [ "\(q)" ]
    }
    """)
    let query = UnresolvedQuery(data: promise)
    self.unresolvedQueries[id] = query
    return try await query.resolve()
  }

  func queryFirst<T: Decodable>(as: T.Type, _ q: String) async throws -> T? {
    let id = self.getId()
    let promise = self.elg.any().makePromise(of: String.self)

    let _ = try await self.ws.send("""
    {
      "id": \(id),
      "method": "query",
      "params": [ "\(q)" ]
    }
    """)
    let query = UnresolvedQuery(data: promise)
    self.unresolvedQueries[id] = query
    return try await query.resolveFirst()
  }

  func close() -> EventLoopFuture<Void> {
    return self.ws.close()
  }
}

let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
var conn = DbConn(elg: elg)
try await conn.connect()
let queryResult = try await conn.queryFirst(as: Person.self, "select * from person:99t3gb863y5t2s82l28w, person:99o1ox467x1o3k84c06p")
dump(queryResult! as Any)
let _ = conn.close()
