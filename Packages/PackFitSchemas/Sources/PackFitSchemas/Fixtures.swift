import Foundation

/// Loads `schemas/fixtures/` from the package bundle. Fixture-only keys such as `_source`
/// are ignored by the decoder.
public enum Fixtures {
    public static func items() throws -> [Item] { try load("items") }
    public static func containers() throws -> [Container] { try load("containers") }
    public static func trips() throws -> [Trip] { try load("trips") }

    /// A pre-computed plan, named `<trip-id>-<bag>`, e.g. `"sfo-del-checked"`.
    public static func plan(named name: String) throws -> Plan { try load(name) }

    /// Raw bytes of a fixture file, by base name (`"items"`, `"sfo-del-checked"`, ...).
    public static func data(named name: String) throws -> Data {
        // `.process` flattens schemas/fixtures/** into the bundle root.
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    private static func load<T: Decodable>(_ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(named: name))
    }
}

public enum FixtureError: Error, Equatable {
    case notFound(String)
}
