@_exported import PackFitSchemas

/// Foundation also exports the Objective-C runtime's `Category`; this app-level alias wins
/// over both imports so unqualified `Category` always means the schema enum.
typealias Category = PackFitSchemas.Category
