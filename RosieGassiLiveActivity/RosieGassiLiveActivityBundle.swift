import SwiftUI
import WidgetKit

/// Einstiegspunkt der Widget-Extension.
///
/// Die Extension enthält bewusst nur Darstellung und die deklarativen
/// `LiveActivityIntent`-Typen aus dem gemeinsamen Vertrag. Sie startet keine Ortung,
/// liest keinen Store und schreibt nichts.
@main
struct RosieGassiLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        WalkActivityLiveActivity()
    }
}
