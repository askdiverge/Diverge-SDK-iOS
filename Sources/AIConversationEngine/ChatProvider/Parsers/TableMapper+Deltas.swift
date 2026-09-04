//
//  TableMapper+Deltas.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-06-17.
//

extension TableMapper {

    /// Reconstructs a `TableContent` from the streamed table deltas: `.start` carries the
    /// columns/alignment/caption, `.appendRow` the rows. Nil until the part has started.
    static func content(_ deltas: [PartDelta.TableDelta]) -> TableContent? {
        guard
            let start = deltas.compactMap({ delta -> PartDelta.TableDelta.StartTable? in
                guard case .start(let start) = delta else { return nil }
                return start
            }).first
        else {
            return nil
        }

        let rows = deltas.compactMap { delta -> [Table.Cell]? in
            guard case .appendRow(let row) = delta else { return nil }
            return row
        }

        return self.content(
            caption: start.caption,
            headers: start.headers,
            alignments: start.alignments,
            rows: rows
        )
    }
}
