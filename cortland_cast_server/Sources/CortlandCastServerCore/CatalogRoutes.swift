import Foundation
import Vapor
import MusicKit

// Extension on MusicServer to register catalog and MusicKit routes
extension MusicServer {

    func catalogRoutes(_ app: Application) throws {

        // MARK: - MusicKit Status & Authorization

        app.get("musickit", "status") { req async -> Response in
            serverLog("GET /musickit/status", level: "INFO")
            let status = await MusicKitService.shared.getStatus()
            do {
                return try await status.encodeResponse(for: req)
            } catch {
                serverLog("Failed to encode MusicKit status: \(error)", level: "ERROR")
                return Response(status: .internalServerError, body: .init(string: "{\"error\": \"Failed to encode status\"}"))
            }
        }

        app.post("musickit", "authorize") { req async -> Response in
            serverLog("POST /musickit/authorize", level: "INFO")
            let status = await MusicKitService.shared.requestAuthorization()
            let authorized = status == .authorized
            serverLog("MusicKit authorization result: \(status)", level: "INFO")
            let json = "{\"authorized\": \(authorized), \"status\": \"\(status)\"}"
            return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(string: json))
        }

        // MARK: - Catalog Search

        app.get("catalog", "search") { req async -> Response in
            guard let query = req.query[String.self, at: "q"], !query.isEmpty else {
                return Response(status: .badRequest, body: .init(string: "{\"error\": \"Missing required parameter: q\"}"))
            }

            let typesParam = req.query[String.self, at: "types"]
            let types: Set<String>? = typesParam.map { Set($0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }) }
            let limit = req.query[Int.self, at: "limit"] ?? 25

            serverLog("GET /catalog/search q=\(query) types=\(typesParam ?? "all") limit=\(limit)", level: "INFO")

            do {
                let result = try await MusicKitService.shared.searchCatalog(term: query, types: types, limit: limit)
                return try await result.encodeResponse(for: req)
            } catch let error as MusicKitServiceError {
                serverLog("Catalog search error: \(error)", level: "ERROR")
                let status: HTTPResponseStatus = error.description.contains("not authorized") ? .forbidden : .internalServerError
                return Response(status: status, body: .init(string: "{\"error\": \"\(error.description)\"}"))
            } catch {
                serverLog("Catalog search error: \(error)", level: "ERROR")
                return Response(status: .internalServerError, body: .init(string: "{\"error\": \"Search failed: \(error.localizedDescription)\"}"))
            }
        }

        // MARK: - Charts

        app.get("catalog", "charts") { req async -> Response in
            let limit = req.query[Int.self, at: "limit"] ?? 25
            serverLog("GET /catalog/charts limit=\(limit)", level: "INFO")

            do {
                let result = try await MusicKitService.shared.getCharts(limit: limit)
                return try await result.encodeResponse(for: req)
            } catch let error as MusicKitServiceError {
                serverLog("Catalog charts error: \(error)", level: "ERROR")
                let status: HTTPResponseStatus = error.description.contains("not authorized") ? .forbidden : .internalServerError
                return Response(status: status, body: .init(string: "{\"error\": \"\(error.description)\"}"))
            } catch {
                serverLog("Catalog charts error: \(error)", level: "ERROR")
                return Response(status: .internalServerError, body: .init(string: "{\"error\": \"Charts failed: \(error.localizedDescription)\"}"))
            }
        }

        // MARK: - Catalog Album

        app.get("catalog", "album", ":id") { req async -> Response in
            guard let id = req.parameters.get("id") else {
                return Response(status: .badRequest, body: .init(string: "{\"error\": \"Missing album ID\"}"))
            }
            serverLog("GET /catalog/album/\(id)", level: "INFO")

            do {
                let result = try await MusicKitService.shared.getCatalogAlbum(id: id)
                return try await result.encodeResponse(for: req)
            } catch let error as MusicKitServiceError {
                serverLog("Catalog album error: \(error)", level: "ERROR")
                let status: HTTPResponseStatus = error.description.contains("not found") ? .notFound : .internalServerError
                return Response(status: status, body: .init(string: "{\"error\": \"\(error.description)\"}"))
            } catch {
                serverLog("Catalog album error: \(error)", level: "ERROR")
                return Response(status: .internalServerError, body: .init(string: "{\"error\": \"Album fetch failed: \(error.localizedDescription)\"}"))
            }
        }

        // MARK: - Catalog Playlist

        app.get("catalog", "playlist", ":id") { req async -> Response in
            guard let id = req.parameters.get("id") else {
                return Response(status: .badRequest, body: .init(string: "{\"error\": \"Missing playlist ID\"}"))
            }
            serverLog("GET /catalog/playlist/\(id)", level: "INFO")

            do {
                let result = try await MusicKitService.shared.getCatalogPlaylist(id: id)
                return try await result.encodeResponse(for: req)
            } catch let error as MusicKitServiceError {
                serverLog("Catalog playlist error: \(error)", level: "ERROR")
                let status: HTTPResponseStatus = error.description.contains("not found") ? .notFound : .internalServerError
                return Response(status: status, body: .init(string: "{\"error\": \"\(error.description)\"}"))
            } catch {
                serverLog("Catalog playlist error: \(error)", level: "ERROR")
                return Response(status: .internalServerError, body: .init(string: "{\"error\": \"Playlist fetch failed: \(error.localizedDescription)\"}"))
            }
        }

        // MARK: - Catalog Artist

        app.get("catalog", "artist", ":id") { req async -> Response in
            guard let id = req.parameters.get("id") else {
                return Response(status: .badRequest, body: .init(string: "{\"error\": \"Missing artist ID\"}"))
            }
            serverLog("GET /catalog/artist/\(id)", level: "INFO")

            do {
                let result = try await MusicKitService.shared.getCatalogArtist(id: id)
                return try await result.encodeResponse(for: req)
            } catch let error as MusicKitServiceError {
                serverLog("Catalog artist error: \(error)", level: "ERROR")
                let status: HTTPResponseStatus = error.description.contains("not found") ? .notFound : .internalServerError
                return Response(status: status, body: .init(string: "{\"error\": \"\(error.description)\"}"))
            } catch {
                serverLog("Catalog artist error: \(error)", level: "ERROR")
                return Response(status: .internalServerError, body: .init(string: "{\"error\": \"Artist fetch failed: \(error.localizedDescription)\"}"))
            }
        }

        // MARK: - Recommendations

        app.get("catalog", "recommendations") { req async -> Response in
            serverLog("GET /catalog/recommendations", level: "INFO")

            do {
                let result = try await MusicKitService.shared.getRecommendations()
                let encoder = JSONEncoder()
                let data = try encoder.encode(result)
                return Response(status: .ok, headers: ["Content-Type": "application/json"], body: .init(data: data))
            } catch let error as MusicKitServiceError {
                serverLog("Catalog recommendations error: \(error)", level: "ERROR")
                let status: HTTPResponseStatus = error.description.contains("not authorized") ? .forbidden : .internalServerError
                return Response(status: status, body: .init(string: "{\"error\": \"\(error.description)\"}"))
            } catch {
                serverLog("Catalog recommendations error: \(error)", level: "ERROR")
                return Response(status: .internalServerError, body: .init(string: "{\"error\": \"Recommendations failed: \(error.localizedDescription)\"}"))
            }
        }
    }
}
