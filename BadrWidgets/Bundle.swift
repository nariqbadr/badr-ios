import WidgetKit
import SwiftUI

/// the widgets (in a file of its own: the widget preview app used in the tests leaves it out)
@main
struct BadrWidgets: WidgetBundle {
    var body: some Widget {
        DayWidget(); DayCalligWidget(); DayFrameWidget(); PrayerWidget(); RamadanWidget()
        AyahWidget(); NowWidget(); DhikrWidget(); MoreWidgets().body
    }
}
