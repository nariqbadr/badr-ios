import SwiftUI

/// «الحرم المكي · المسجد النبوي»: switches the stream (the choice is remembered).
struct MosqueChips: View {
    @Binding var mosque: String
    var onDark = false
    @Environment(\.pal) private var c
    var body: some View {
        if Haram.madinahOn {
            HStack(spacing: 4) {
                ForEach(["mk", "md"], id: \.self) { k in
                    let on = mosque == k
                    Button { Haram.choose(k); withAnimation(.easeOut(duration: 0.25)) { mosque = k } } label: {
                        Text(k == "md" ? tr("المسجد النبوي") : tr("الحرم المكي")).font(F.plex(12.5, .bold))
                            .foregroundStyle(on ? c.onGold : (onDark ? .white : c.text))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(on ? AnyShapeStyle(c.goldBrush) : AnyShapeStyle(Color.clear)))
                    }.buttonStyle(.plain)
                }
            }.padding(4).background(Capsule().fill(onDark ? Color.black.opacity(0.55) : c.surface)).overlay(Capsule().stroke(onDark ? .white.opacity(0.15) : c.line))
        }
    }
}

/// «الأذان · الإقامة · الصلاة»: where the mosque is now.
struct HaramSteps: View {
    let step: Int
    @Environment(\.pal) private var c
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array([tr("الأذان"), tr("الإقامة"), tr("الصلاة")].enumerated()), id: \.offset) { i, t in
                Text(t).font(F.plex(10, step == i + 1 ? .bold : .medium))
                    .foregroundStyle(step == i + 1 ? c.onGold : step > i ? Color(hex: 0xFFE3C88D) : .white.opacity(0.55))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(step == i + 1 ? AnyShapeStyle(c.goldBrush) : AnyShapeStyle(Color.white.opacity(0.08))))
            }
        }
    }
}

/// The mosque's moment over the stream: the next adhan, the adhan, the wait for the iqama, the prayer — in gold.
struct HaramStateBox: View {
    let st: Haram.State
    @Environment(\.pal) private var c
    var body: some View {
        let now = st.kind != "next"
        VStack(spacing: 2) {
            Text(st.label).font(F.plex(11)).foregroundStyle(Color(hex: 0xFFE3C88D)).lineLimit(1)
            Text(st.value).font(st.kind == "now" ? F.amiri(17, bold: true) : F.plex(15, .bold)).foregroundStyle(now ? Color(hex: 0xFFF3DFAE) : .white)
                .monospacedDigit().environment(\.layoutDirection, st.kind == "now" ? L.dir : .leftToRight)
            if st.step > 0 { HaramSteps(step: st.step).padding(.top, 3) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14).fill(now ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x61C9A45C), Color(hex: 0x8C0C1715)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color(hex: 0xAA000000))))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(now ? c.gold.opacity(0.7) : Color.white.opacity(0.12)))
    }
}

/// The imam's photo in an arch (or his initial).
struct ImamPic: View {
    let p: Haram.Person?; var size: CGFloat = 56; var glow = false
    @Environment(\.pal) private var c
    var body: some View {
        let shape = ArchShape()
        ZStack {
            shape.fill(c.surface2)
            if let ph = p?.photo, !ph.isEmpty { RemoteImage(raw: ph).clipShape(shape) }
            else { Text(String((p?.nameAr ?? "؟").replacingOccurrences(of: "أ.د. ", with: "").replacingOccurrences(of: "د. ", with: "").prefix(1))).font(F.amiri(size * 0.4, bold: true)).foregroundStyle(c.gold) }
        }
        .frame(width: size, height: size * 1.18)
        .overlay(shape.stroke(LinearGradient(colors: [c.gold2, c.gold], startPoint: .top, endPoint: .bottom), lineWidth: 1.6))
        .shadow(color: glow ? c.gold.opacity(0.45) : .clear, radius: glow ? 10 : 0)
    }
}

/// «تابع الشيخ» / «متابَع».
struct FollowButton: View {
    let id: String
    @State private var on = false
    @Environment(\.pal) private var c
    var body: some View {
        Button {
            on.toggle(); Haram.setFollow(id, on)
            UIState.shared?.toast = on ? tr("سيصلك تنبيه قبل صلاة الشيخ") : tr("أُلغيت المتابعة")
        } label: {
            HStack(spacing: 6) { SiteIcon(name: on ? "check" : "bell", size: 16, color: on ? c.onGold : c.gold); Text(on ? tr("متابَع") : tr("تابع الشيخ")).font(F.plex(13, .bold)).foregroundStyle(on ? c.onGold : c.text) }
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(Capsule().fill(on ? AnyShapeStyle(c.goldBrush) : AnyShapeStyle(c.surface)))
                .overlay(Capsule().stroke(on ? Color.clear : c.gold.opacity(0.5)))
        }.buttonStyle(Press()).onAppear { on = Haram.follows.contains(id) }
    }
}

/// «البث المباشر»: the stream of the chosen mosque, what is happening there now, who leads, and today's imams.
struct HaramLiveView: View {
    var start: String = ""
    @EnvironmentObject var repo: Repo
    @EnvironmentObject var ui: UIState
    @Environment(\.pal) private var c
    @StateObject private var ctl = LiveCtl()
    @State private var mosque = Haram.chosen
    @State private var sound = true
    @State private var key = 0
    var body: some View {
        let src = Haram.src(mosque), m = Haram.mosque(mosque)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LiveEmbedFull(id: src.embed, ctl: ctl).id("\(mosque)\(key)").aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(c.line))
                HStack { Spacer(); MosqueChips(mosque: $mosque); Spacer() }
                VStack(spacing: 2) {
                    Text(tr("البث المباشر · {0}", m.city)).font(F.plex(12)).foregroundStyle(c.gold)
                    Text(m.name).font(F.amiri(28, bold: true)).foregroundStyle(c.text)
                }.frame(maxWidth: .infinity)
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let st = Haram.state(mosque, tl.date)
                    VStack(spacing: 8) {
                        HStack {
                            Text(st.label).font(F.plex(14)).foregroundStyle(c.muted)
                            Spacer()
                            Text(st.value).font(st.kind == "now" ? F.amiri(19, bold: true) : F.plex(17, .bold)).foregroundStyle(c.gold2).monospacedDigit()
                                .environment(\.layoutDirection, st.kind == "now" ? L.dir : .leftToRight)
                        }
                        if !st.sub.isEmpty { Text(st.sub).font(F.plex(12.5)).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .leading) }
                        if st.step > 0 { HaramSteps(step: st.step).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                    .padding(14).background(RoundedRectangle(cornerRadius: 16).fill(st.kind == "next" ? AnyShapeStyle(c.surface) : AnyShapeStyle(c.gold.opacity(0.12))))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(st.kind == "next" ? c.line : c.gold.opacity(0.6)))
                }
                HStack(spacing: 8) {
                    Chip(text: sound ? tr("كتم الصوت") : tr("تشغيل الصوت"), icon: sound ? "mute" : "volume") { sound.toggle(); if sound { AdhanPlayer.shared.stop() }; ctl.js(sound ? "cmd('unMute');cmd('setVolume',[100]);cmd('playVideo')" : "cmd('mute')") }
                    Chip(text: tr("إعادة تحميل"), icon: "refresh") { key += 1 }
                    Chip(text: "YouTube", icon: "external") { if let u = URL(string: src.url) { UIApplication.shared.open(u) } }
                }
                if let n = Haram.next(mosque), let p = n.imam {
                    HStack(alignment: .top, spacing: 14) {
                        ImamPic(p: p, size: 76, glow: true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("يؤم صلاة {0} · {1}", n.key == "jumuah" ? tr("الجمعة") : Haram.prayerName(n.key), Haram.clock(n.at))).font(F.plex(12)).foregroundStyle(c.gold2)
                            Text(p.title).font(F.plex(11)).foregroundStyle(c.muted)
                            Text(p.full).font(F.amiri(19, bold: true)).foregroundStyle(c.text).fixedSize(horizontal: false, vertical: true)
                            if let b = n.backup { Text(tr("الاحتياطي: الشيخ {0}", b.name)).font(F.plex(11.5)).foregroundStyle(c.muted) }
                            HStack(spacing: 8) {
                                FollowButton(id: p.id)
                                Button { ui.path.append(.imams(mosque)) } label: { Text(tr("الجدول كامل")).font(F.plex(13, .semibold)).foregroundStyle(c.gold).padding(.horizontal, 12).padding(.vertical, 8).overlay(Capsule().stroke(c.line)) }.buttonStyle(.plain)
                            }.padding(.top, 6)
                        }
                        Spacer(minLength: 0)
                    }.padding(14).background(RoundedRectangle(cornerRadius: 20).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 20).stroke(c.gold.opacity(0.35)))
                } else if Haram.week(mosque) == nil || Haram.slots(mosque) == nil {
                    Text(tr("جدول أئمة {0} لهذا الأسبوع لم يُنشر بعد.", m.name)).font(F.plex(13)).foregroundStyle(c.muted)
                }
                if let sl = Haram.slots(mosque) {
                    Text(tr("أئمة اليوم في {0}", m.short)).font(F.plex(15, .bold)).foregroundStyle(c.text)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            let t = Haram.times(mosque)
                            ForEach(Haram.prayerKeys, id: \.self) { k in
                                if let p = Haram.person(sl[k]?.imam) {
                                    VStack(spacing: 4) {
                                        ImamPic(p: p, size: 50)
                                        Text(Haram.prayerName(k)).font(F.plex(11.5, .bold)).foregroundStyle(c.gold)
                                        Text(t[k].map { Haram.clock($0) } ?? "").font(F.plex(10)).foregroundStyle(c.muted)
                                    }.frame(width: 70)
                                }
                            }
                        }
                    }
                    Button { ui.path.append(.imamAlerts) } label: { HStack { SiteIcon(name: "bell", size: 18, color: c.gold); Text(tr("تنبيهات الأئمة")).font(F.plex(14, .semibold)).foregroundStyle(c.text); Spacer(); SiteIcon(name: "chev-l", size: 16, color: c.muted) }.padding(14).background(RoundedRectangle(cornerRadius: 16).fill(c.surface)) }.buttonStyle(.plain)
                }
            }.padding(16)
        }
        .onAppear { if !start.isEmpty { mosque = start; Haram.choose(start) }; AudioPlayer.shared.pause(); AyahPlayer.shared.stop() }
    }
}

/// «جدول أئمة الحرمين»: the week's imams of each mosque, with their photos.
struct ImamsView: View {
    var start: String = ""
    @Environment(\.pal) private var c
    @State private var mosque = Haram.chosen
    var body: some View {
        let m = Haram.mosque(mosque), t = Haram.times(mosque)
        ScrollView {
            VStack(spacing: 14) {
                MosqueChips(mosque: $mosque)
                VStack(spacing: 6) {
                    Text(tr("جدول الأئمة الأسبوعي في")).font(F.amiri(16)).foregroundStyle(c.muted)
                    Text(m.name).font(F.amiri(32, bold: true)).foregroundStyle(c.gold2)
                    if let w = Haram.week(mosque) { Text(tr("من {0} إلى {1}", L.digits(w.from), L.digits(w.to))).font(F.plex(12)).foregroundStyle(c.muted).environment(\.layoutDirection, L.dir) }
                }.padding(.vertical, 18).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 24).fill(c.surface)).overlay(RoundedRectangle(cornerRadius: 24).stroke(c.gold.opacity(0.4)))
                if let sl = Haram.slots(mosque) {
                    let n = Haram.next(mosque)
                    ForEach(Haram.prayerKeys + ["jumuah"], id: \.self) { k in
                        if let s = sl[k], let p = Haram.person(s.imam) {
                            let on = n?.key == k
                            HStack(spacing: 12) {
                                VStack(spacing: 2) {
                                    Text(k == "jumuah" ? tr("الجمعة") : Haram.prayerName(k)).font(F.amiri(16, bold: true)).foregroundStyle(c.gold2).lineLimit(1).minimumScaleFactor(0.7)
                                    Text(k == "jumuah" ? "" : t[k].map { Haram.clock($0) } ?? "").font(F.plex(10.5)).foregroundStyle(c.muted)
                                }.frame(width: 64).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 14).fill(c.gold.opacity(0.1))).overlay(RoundedRectangle(cornerRadius: 14).stroke(c.gold.opacity(0.3)))
                                ImamPic(p: p, size: 54, glow: on)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.title).font(F.plex(10.5)).foregroundStyle(c.gold)
                                    Text(p.full).font(F.amiri(17, bold: true)).foregroundStyle(c.text).fixedSize(horizontal: false, vertical: true)
                                    if let b = Haram.person(s.backup) { Text(tr("الاحتياطي: الشيخ {0}", b.name)).font(F.plex(11)).foregroundStyle(c.muted).lineLimit(1) }
                                }
                                Spacer(minLength: 0)
                            }.padding(12).background(RoundedRectangle(cornerRadius: 20).fill(on ? c.gold.opacity(0.1) : c.surface)).overlay(RoundedRectangle(cornerRadius: 20).stroke(on ? c.gold : c.line))
                        }
                    }
                } else {
                    Text(tr("جدول أئمة {0} لهذا الأسبوع لم يُنشر بعد. يُحدَّث كل أسبوع من إدارة التطبيق.", m.name)).font(F.plex(13.5)).foregroundStyle(c.muted).multilineTextAlignment(.center).padding(24)
                }
            }.padding(16)
        }
        .onAppear { if !start.isEmpty { mosque = start } }
    }
}

/// «تنبيهات الأئمة»: when the alert comes, and which imams of each mosque the person follows.
struct ImamAlertsView: View {
    @Environment(\.pal) private var c
    @State private var when = Haram.whenMode
    @State private var backup = Haram.backupToo
    @State private var rev = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("تابع المشايخ الذين تحبهم، ويصلك تنبيه حين يؤم أحدهم صلاة في الحرم المكي أو المسجد النبوي، حسب جدول الأسبوع.")).font(F.plex(13)).foregroundStyle(c.muted)
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("متى يصلك التنبيه؟")).font(F.plex(14, .bold)).foregroundStyle(c.text)
                    ForEach(Array([tr("عند الأذان"), tr("قبل الإقامة بـ ١٠ دقائق"), tr("قبل الصلاة بنصف ساعة")].enumerated()), id: \.offset) { i, t in
                        Button { when = i; Haram.whenMode = i; Haram.schedule() } label: {
                            HStack { Text(t).font(F.plex(13.5, when == i ? .bold : .regular)).foregroundStyle(when == i ? c.gold2 : c.text); Spacer(); if when == i { SiteIcon(name: "check", size: 18, color: c.gold) } }
                                .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(when == i ? c.gold.opacity(0.12) : c.surface2))
                        }.buttonStyle(.plain)
                    }
                    Toggle(isOn: $backup) { Text(tr("نبّهني أيضًا حين يكون الشيخ إمامًا احتياطيًا")).font(F.plex(13)).foregroundStyle(c.text) }
                        .tint(c.gold).onChange(of: backup) { v in Haram.backupToo = v; Haram.schedule() }
                }.padding(14).background(RoundedRectangle(cornerRadius: 18).fill(c.surface))
                ForEach(["mk", "md"], id: \.self) { k in
                    let ppl = Haram.people().filter { $0.mosque == k }
                    if !ppl.isEmpty {
                        Text(tr("أئمة {0}", Haram.mosque(k).name)).font(F.plex(15, .bold)).foregroundStyle(c.text).padding(.top, 4)
                        ForEach(ppl) { p in
                            HStack(spacing: 12) {
                                ImamPic(p: p, size: 42)
                                VStack(alignment: .leading, spacing: 1) { Text(tr("الشيخ {0}", p.name)).font(F.plex(14, .semibold)).foregroundStyle(c.text); Text(p.title).font(F.plex(11)).foregroundStyle(c.muted) }
                                Spacer()
                                Toggle("", isOn: Binding(get: { _ = rev; return Haram.follows.contains(p.id) }, set: { Haram.setFollow(p.id, $0); rev += 1 })).labelsHidden().tint(c.gold)
                            }.padding(10).background(RoundedRectangle(cornerRadius: 16).fill(c.surface))
                        }
                    }
                }
            }.padding(16)
        }
    }
}

/// A mihrab arch: a round top over straight sides.
struct ArchShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let rad = r.width / 2
        p.move(to: CGPoint(x: r.minX, y: r.maxY - 8))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
        p.addArc(center: CGPoint(x: r.midX, y: r.minY + rad), radius: rad, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 8))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 8, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 8, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 8), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath(); return p
    }
}
