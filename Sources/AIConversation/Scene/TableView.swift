//
//  TableView.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-08.
//

import SwiftUI
import AIConversationEngine

/// Renders a `TableContent` through `DataGrid` — maps the columns/rows/alignment and populates the
/// cell blocks (parsed rich text + product imagery).
struct TableView: View {

    @Environment(\.appearance) private var appearance

    let content: TableContent

    /// The table's rendered width, measured so image cells can derive a definite height.
    @State private var tableWidth: CGFloat = 0

    /// Columns share the width equally, so the image height follows the 0.7 ratio of a single
    /// column's content area. Definite (not width-derived), which the grid's cells require.
    private var imageHeight: CGFloat {
        let columns = CGFloat(max(self.content.columns.count, 1))
        let columnWidth = self.tableWidth / columns
        let contentWidth = columnWidth - self.appearance.spacing.units(2) * 2
        return max(contentWidth, 0) / 0.7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: self.appearance.spacing.units(2)) {
            if let caption = self.content.caption {
                Text(caption)
                    .font(self.appearance.font(size: 13))
                    .foregroundStyle(self.appearance.theme.primaryText)
            }

            DataGrid(
                columns: self.content.columns.count,
                alignments: self.content.columns.map { $0.alignment.horizontal },
                header: self.content.columns.map { $0.header },
                rows: self.content.rows,
                style: .init(
                    padding: self.appearance.spacing.units(2),
                    headerBackground: self.appearance.theme.background,
                    rowBackground: self.appearance.theme.botSurface,
                    stroke: self.appearance.theme.botSurfaceBorder
                ),
                headerCell: { self.blocks($0) },
                bodyCell: { self.blocks($0) }
            )
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                self.tableWidth = width
            }
        }
    }

    @ViewBuilder
    private func blocks(_ cell: TableContent.Cell) -> some View {
        ForEach(Array(cell.elements.enumerated()), id: \.offset) { _, element in
            self.element(element)
        }
    }

    @ViewBuilder
    private func element(_ element: TableContent.Cell.Element) -> some View {
        switch element {
        case .text(let text):
            Text(text)
                .font(self.appearance.font(size: 13))
                .foregroundStyle(self.appearance.theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)

        case .image(let image):
            // Cached + coalesced loader: the streaming re-renders resolve from cache instead of
            // restarting the download.
            Color.clear
                .frame(height: self.imageHeight)
                .overlay {
                    RemoteImageView(url: image.url) { result in
                        switch result {
                        case .success(let loaded):
                            loaded.resizable().scaledToFill()
                        case .failure:
                            // TODO: replace with a real image-failure view
                            EmptyView()
                        }
                    } placeholder: {
                        ProgressView()
                            .tint(self.appearance.theme.accent)
                    }
                }
                .background(self.appearance.theme.botSurface)
                .clipped()
        }
    }
}

private extension TableContent.Alignment {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }
}
