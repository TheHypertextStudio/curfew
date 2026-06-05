#!/usr/bin/env swift
// Usage: swift scripts/window-id.swift [ownerName]
//
// Prints the CGWindowID of the largest on-screen window owned by `ownerName`
// (default "Curfew"), suitable for `screencapture -l <id>`. Exits non-zero
// when no matching window is on screen. Dependency-free — uses only
// CoreGraphics from the system toolchain.

import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Curfew"

guard let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("window-id: could not list windows\n".utf8))
    exit(2)
}

struct Candidate {
    let id: CGWindowID
    let area: CGFloat
}

var best: Candidate?
for window in windows {
    guard let windowOwner = window[kCGWindowOwnerName as String] as? String,
          windowOwner == owner,
          let number = window[kCGWindowNumber as String] as? CGWindowID,
          let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
          let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
    else { continue }

    let area = bounds.width * bounds.height
    if best == nil || area > best!.area {
        best = Candidate(id: number, area: area)
    }
}

guard let best else {
    FileHandle.standardError.write(Data("window-id: no on-screen window for owner \(owner)\n".utf8))
    exit(1)
}

print(best.id)
