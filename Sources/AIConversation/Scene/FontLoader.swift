//
//  FontLoader.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-31.
//

import CoreText
import Foundation

/// Caches, registers, and resolves the remote native font, returning the family name the system indexes it
/// under — the string the chat feeds to `Font.custom`.
///
/// Registration needs a font *file* (`CTFontManagerRegisterFontsForURL`); descriptors parsed straight from
/// data can't be registered. So the asset is written to a single-slot on-disk cache keyed by its sha: an
/// unchanged font is a hit (no download), a changed one misses and replaces the slot. Only one font is ever
/// kept, so traversing dashboards never accumulates stale files.
///
/// The family is resolved *through the registry* (create a font by a face's PostScript name, read its family
/// back), not off the raw data — the data's family entry can differ from the installed name (e.g. `Suisse
/// Int'l`). `nil` when the asset can't be fetched, cached, or registered, and the chat falls back to system.
enum FontLoader {

    private static let cacheDirectory = "AIConversation/fonts"

    static func loadFamily(
        url: URL,
        sha256: String,
        format: String,
        fetch: @Sendable (URL) async throws -> Data
    ) async -> String? {
        guard let slot = Self.cacheSlot(sha256: sha256, format: format) else { return nil }

        if !FileManager.default.fileExists(atPath: slot.path) {
            guard let data = try? await fetch(url) else { return nil }
            Self.deleteAll(except: slot)
            guard (try? data.write(to: slot)) != nil else { return nil }
        }

        // Register, best effort.
        // Concrete font resolvability is exclusively settled by `resolvedFamily`, not this call's result.
        // Fresh, already-registered or a name the host already claimed with its own copy is irrelevant,
        // as long as family can be resolved the font is accessible.
        _ = CTFontManagerRegisterFontsForURL(slot as CFURL, .process, nil)

        guard let family = Self.resolvedFamily(slot) else {
            // Unusable/bad data, or the name never resolved.
            // Drop it so a good copy re-downloads next launch instead of a poisoned cache re-failing forever.
            try? FileManager.default.removeItem(at: slot)
            return nil
        }

        return family
    }
}

// MARK: - Cache

private extension FontLoader {

    /// The single cache slot, under Caches and named by the asset sha.
    static func cacheSlot(sha256: String, format: String) -> URL? {
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else {
            return nil
        }
        let directory = caches.appendingPathComponent(Self.cacheDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(sha256).appendingPathExtension(format)
    }

    /// Drops every cached font but `slot` — the single-slot guarantee.
    static func deleteAll(except slot: URL) {
        let directory = slot.deletingLastPathComponent()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        for file in contents where file != slot {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// MARK: - Registration & resolution

private extension FontLoader {

    /// Resolves the installed family by round-tripping the regular face's PostScript name through the
    /// registry — creating a font *by name* reports the family the system indexes, apostrophes and all.
    static func resolvedFamily(_ url: URL) -> String? {
        guard
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            let faceName = Self.regularFaceName(descriptors)
        else {
            return nil
        }
        let font = CTFontCreateWithName(faceName as CFString, 0, nil)
        // `CTFontCreateWithName` never fails — an unregistered name yields a system fallback. Reject that
        // (its PostScript name won't match) so a failed load degrades to system, not a mislabelled family.
        guard CTFontCopyPostScriptName(font) as String == faceName else { return nil }
        return CTFontCopyFamilyName(font) as String
    }

    /// The PostScript name of the upright face nearest regular weight — the base the system resolves other
    /// weights and inline emphasis against. An outlier weight can report a split sub-family, so the regular
    /// face is the one carrying the shared family name.
    static func regularFaceName(_ descriptors: [CTFontDescriptor]) -> String? {
        descriptors
            .compactMap(Self.uprightFace)
            .min { abs($0.weight) < abs($1.weight) }
            .map(\.name)
    }

    static func uprightFace(_ descriptor: CTFontDescriptor) -> (name: String, weight: CGFloat)? {
        guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else {
            return nil
        }
        let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any]
        let symbolic = (traits?[kCTFontSymbolicTrait as String] as? NSNumber)?.uint32Value ?? 0
        guard !CTFontSymbolicTraits(rawValue: symbolic).contains(.traitItalic) else { return nil }
        let weight = (traits?[kCTFontWeightTrait as String] as? NSNumber)?.doubleValue ?? 0
        return (name, CGFloat(weight))
    }
}
