import SwiftUI
import WidgetKit

// Fundo full-bleed — paridade visual com Android (sem margem interna do sistema).
// iOS 17+: containerBackground no conteúdo (WidgetExtension).
// iOS 15.5–16: ZStack (deployment target ML Kit).
// contentMarginsDisabled() fica no WidgetConfiguration (WisdomappWidget.swift).
extension View {
    @ViewBuilder
    func widgetFullBleedBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.widgetFullBleedContainerBackground(color)
        } else {
            ZStack(alignment: .topLeading) {
                color
                    .ignoresSafeArea()
                self
            }
        }
    }

    @available(iOSApplicationExtension 17.0, *)
    @ViewBuilder
    fileprivate func widgetFullBleedContainerBackground(_ color: Color) -> some View {
        containerBackground(for: .widget) {
            color
        }
    }
}
