//
//  CheckboxToggleStyle.swift
//  AIConversation
//
//  Created by Daniel Wennberg on 2026-07-30.
//

import SwiftUI

/// A checkbox toggle — a square box
struct CheckboxToggleStyle: ToggleStyle {

    @Environment(\.appearance) private var appearance

    let isInvalid: Bool

    private var theme: ChatAppearance.Theme {
        self.appearance.theme
    }

    private var spacing: ChatAppearance.Spacing {
        self.appearance.spacing
    }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: self.spacing.units(4)) {
                self.box(isOn: configuration.isOn)
                configuration.label
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func box(isOn: Bool) -> some View {
        Rectangle()
            .fill(self.fill(isOn: isOn))
            .stroke(self.stroke(isOn: isOn), lineWidth: 1)
            .frame(width: self.spacing.units(6), height: self.spacing.units(6))
            .overlay {
                if isOn {
                    ChatAppearance.Symbol.checkmark
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(self.theme.background)
                }
            }
    }

    private func fill(isOn: Bool) -> Color {
        if isOn {
            self.theme.primaryText
        } else if self.isInvalid {
            self.theme.errorBackground
        } else {
            self.theme.background
        }
    }

    private func stroke(isOn: Bool) -> Color {
        if isOn {
            self.theme.primaryText
        } else if self.isInvalid {
            self.theme.destructive
        } else {
            self.theme.outline
        }
    }
}
