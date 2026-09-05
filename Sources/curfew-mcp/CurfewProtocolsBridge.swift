import CurfewProtocols

// CurfewProtocols bridge for the curfew-mcp SPM target.
//
// The curfew-protocols v0.0.9 release supplies the Swift face of the shared
// wire-format contract at this binary's call sites. It ships the same `MCPPendingRequest`,
// `MCPWriteTool`, and `MCPRequestStatus` shapes already declared in
// `Sources/CurfewKit/MCP/MCPPendingRequest.swift` — both are wire-
// compatible because the JSON Schemas in curfew-protocols were
// extracted from the Swift source verbatim.
//
// This file exists today to *consume* the CurfewProtocols package from
// SPM so dependency resolution is exercised by `swift build` and CI
// catches version drift. The internal typealiases below are not
// referenced by curfew-mcp's runtime code; the implementation goal that
// follows the repo split is expected to:
//   1. Delete the inline shapes from `Sources/CurfewKit/MCP/...`
//   2. Add curfew-protocols as a Curfew app target dependency through
//      the Xcode project (File → Add Package Dependencies)
//   3. Replace all consumers' `MCPPendingRequest` (etc.) references
//      with the CurfewProtocols types via `import CurfewProtocols`
//
// Until then, keeping these typealiases under `internal` access avoids
// polluting curfew-mcp's symbol surface.

typealias BridgeMCPPendingRequest = CurfewProtocols.MCPPendingRequest
typealias BridgeMCPWriteTool = CurfewProtocols.MCPWriteTool
typealias BridgeMCPRequestStatus = CurfewProtocols.MCPRequestStatus
typealias BridgeMCPToolRegistry = CurfewProtocols.MCPToolRegistry
