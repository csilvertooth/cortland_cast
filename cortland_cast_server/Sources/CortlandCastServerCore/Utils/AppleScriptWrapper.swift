import Foundation

struct AppleScriptResult {
    let success: Bool
    let output: String
    let error: String
}

func runAppleScript(_ script: String) -> AppleScriptResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        return AppleScriptResult(success: process.terminationStatus == 0, output: output, error: error)
    } catch {
        return AppleScriptResult(success: false, output: "", error: error.localizedDescription)
    }
}

func appleScriptEscape(_ input: String) -> String {
    return input.replacingOccurrences(of: "\"", with: "\\\"")
}
