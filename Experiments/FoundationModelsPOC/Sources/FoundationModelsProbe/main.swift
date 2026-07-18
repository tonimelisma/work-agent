import FoundationModelsPOC

let cases = ["deepseek", "google", "anthropic"]
if CommandLine.arguments.dropFirst().first == "--help" {
    print("Usage: foundation-models-probe <deepseek|google|anthropic>")
    print("Live credentials are intentionally not read until the transport executors are implemented.")
} else {
    print("No live probe was run. Use --help for supported provider cases.")
}
