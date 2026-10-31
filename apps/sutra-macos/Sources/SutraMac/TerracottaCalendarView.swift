import AppKit

public final class TerracottaCalendarView: NSView {
    public var selectedDate: Date? {
        didSet { renderGrid() }
    }
    public var onDateSelected: ((Date) -> Void)?

    private var displayMonth: Date
    private let cal = Calendar.current
    private let titleLabel = NSTextField(labelWithString: "")
    private var gridContainer = NSView()

    public init(frame: NSRect, initialDate: Date = Date()) {
        self.displayMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: initialDate)) ?? initialDate
        self.selectedDate = initialDate
        super.init(frame: frame)
        setupUI()
        renderGrid()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        wantsLayer = true

        // Top Month Navigation: [‹]  [October 2026]  [›]
        let barY = bounds.height - 38
        let navStyle = NSMutableParagraphStyle()
        navStyle.alignment = .center

        let prevBtn = NSButton(frame: NSRect(x: 10, y: barY, width: 32, height: 28))
        prevBtn.attributedTitle = NSAttributedString(string: "‹", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .paragraphStyle: navStyle
        ])
        prevBtn.isBordered = false
        prevBtn.wantsLayer = true
        prevBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        prevBtn.layer?.cornerRadius = 6
        prevBtn.target = self
        prevBtn.action = #selector(onPrevMonth)
        addSubview(prevBtn)

        titleLabel.frame = NSRect(x: 48, y: barY + 2, width: bounds.width - 96, height: 24)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .white
        addSubview(titleLabel)

        let nextBtn = NSButton(frame: NSRect(x: bounds.width - 42, y: barY, width: 32, height: 28))
        nextBtn.attributedTitle = NSAttributedString(string: "›", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 18, weight: .bold),
            .paragraphStyle: navStyle
        ])
        nextBtn.isBordered = false
        nextBtn.wantsLayer = true
        nextBtn.layer?.backgroundColor = NSColor(calibratedWhite: 0.18, alpha: 1.0).cgColor
        nextBtn.layer?.cornerRadius = 6
        nextBtn.target = self
        nextBtn.action = #selector(onNextMonth)
        addSubview(nextBtn)

        // Weekday Column Headers
        let days = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        let colW = (bounds.width - 16) / 7
        let headerY = barY - 26
        for (i, d) in days.enumerated() {
            let lbl = NSTextField(labelWithString: d)
            lbl.frame = NSRect(x: 8 + CGFloat(i) * colW, y: headerY, width: colW, height: 18)
            lbl.alignment = .center
            lbl.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            lbl.textColor = (i == 0 || i == 6) ? NSColor(calibratedWhite: 0.50, alpha: 1.0) : NSColor(calibratedWhite: 0.65, alpha: 1.0)
            addSubview(lbl)
        }

        // Grid Container
        gridContainer.frame = NSRect(x: 8, y: 0, width: bounds.width - 16, height: headerY - 6)
        addSubview(gridContainer)
    }

    @objc private func onPrevMonth() {
        if let newDate = cal.date(byAdding: .month, value: -1, to: displayMonth) {
            displayMonth = newDate
            renderGrid()
        }
    }

    @objc private func onNextMonth() {
        if let newDate = cal.date(byAdding: .month, value: 1, to: displayMonth) {
            displayMonth = newDate
            renderGrid()
        }
    }

    private func renderGrid() {
        gridContainer.subviews.forEach { $0.removeFromSuperview() }

        let df = DateFormatter()
        df.dateFormat = "MMMM yyyy"
        titleLabel.stringValue = df.string(from: displayMonth)

        guard let monthInterval = cal.dateInterval(of: .month, for: displayMonth),
              let daysRange = cal.range(of: .day, in: .month, for: displayMonth) else { return }

        let firstDayWeekday = cal.component(.weekday, from: monthInterval.start) // 1 = Sunday ... 7 = Saturday
        let startCol = firstDayWeekday - 1 // 0-indexed

        let colW = gridContainer.bounds.width / 7
        let numRows = 6
        let rowH = gridContainer.bounds.height / CGFloat(numRows)

        let today = cal.startOfDay(for: Date())
        let sel = selectedDate.map { cal.startOfDay(for: $0) }

        var prevMonthDays = [Int]()
        if startCol > 0,
           let prevMonth = cal.date(byAdding: .month, value: -1, to: displayMonth),
           let prevRange = cal.range(of: .day, in: .month, for: prevMonth) {
            let count = prevRange.count
            let startDay = count - startCol + 1
            if startDay <= count {
                for d in startDay...count {
                    prevMonthDays.append(d)
                }
            }
        }

        var dayCounter = 1
        let maxDays = daysRange.count
        var nextMonthDay = 1

        for r in 0..<numRows {
            let y = gridContainer.bounds.height - CGFloat(r + 1) * rowH
            for c in 0..<7 {
                let x = CGFloat(c) * colW
                let cellFrame = NSRect(x: x + 1, y: y + 1, width: colW - 2, height: rowH - 2)
                let cellIndex = r * 7 + c

                if cellIndex < startCol {
                    if cellIndex < prevMonthDays.count {
                        let prevDay = prevMonthDays[cellIndex]
                        let btn = createDayButton(day: prevDay, frame: cellFrame, isCurrentMonth: false, isToday: false, isSelected: false)
                        btn.target = self
                        btn.action = #selector(onPrevDayClicked(_:))
                        btn.tag = prevDay
                        gridContainer.addSubview(btn)
                    }
                } else if dayCounter <= maxDays {
                    var comps = cal.dateComponents([.year, .month], from: displayMonth)
                    comps.day = dayCounter
                    let thisDate = cal.date(from: comps)!
                    let isToday = cal.isDate(thisDate, inSameDayAs: today)
                    let isSelected = (sel != nil && cal.isDate(thisDate, inSameDayAs: sel!))

                    let currentDay = dayCounter
                    let btn = createDayButton(day: currentDay, frame: cellFrame, isCurrentMonth: true, isToday: isToday, isSelected: isSelected)
                    btn.target = self
                    btn.action = #selector(onDayClicked(_:))
                    btn.tag = currentDay
                    gridContainer.addSubview(btn)

                    dayCounter += 1
                } else {
                    let nextDay = nextMonthDay
                    let btn = createDayButton(day: nextDay, frame: cellFrame, isCurrentMonth: false, isToday: false, isSelected: false)
                    btn.target = self
                    btn.action = #selector(onNextDayClicked(_:))
                    btn.tag = nextDay
                    gridContainer.addSubview(btn)
                    nextMonthDay += 1
                }
            }
        }
    }

    private func createDayButton(day: Int, frame: NSRect, isCurrentMonth: Bool, isToday: Bool, isSelected: Bool) -> NSButton {
        let btn = NSButton(frame: frame)
        btn.title = "\(day)"
        btn.alignment = .center
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6

        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center

        if isSelected {
            // Terracotta highlight EXCLUSIVELY for the selected date
            btn.layer?.backgroundColor = NSColor(calibratedRed: 0.702, green: 0.337, blue: 0.165, alpha: 1.0).cgColor
            btn.layer?.borderWidth = 0
            btn.attributedTitle = NSAttributedString(string: "\(day)", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .heavy),
                .paragraphStyle: centerStyle
            ])
        } else if isToday {
            // Unselected Today: Crisp neutral silver border with pure white text (no terracotta)
            btn.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1.0).cgColor
            btn.layer?.borderColor = NSColor(calibratedWhite: 0.55, alpha: 0.85).cgColor
            btn.layer?.borderWidth = 1.0
            btn.attributedTitle = NSAttributedString(string: "\(day)", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .paragraphStyle: centerStyle
            ])
        } else if isCurrentMonth {
            // Standard month date: Studio dark background with pure white text
            btn.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1.0).cgColor
            btn.layer?.borderWidth = 0
            btn.attributedTitle = NSAttributedString(string: "\(day)", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .paragraphStyle: centerStyle
            ])
        } else {
            // Adjacent month dates: Subtle muted white text, clickable for fast navigation
            btn.layer?.backgroundColor = NSColor.clear.cgColor
            btn.layer?.borderWidth = 0
            btn.attributedTitle = NSAttributedString(string: "\(day)", attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .paragraphStyle: centerStyle
            ])
        }
        return btn
    }

    @objc private func onDayClicked(_ sender: NSButton) {
        let day = sender.tag
        var comps = cal.dateComponents([.year, .month], from: displayMonth)
        comps.day = day
        if let targetDate = cal.date(from: comps) {
            selectedDate = cal.startOfDay(for: targetDate)
            onDateSelected?(selectedDate!)
        }
    }

    @objc private func onPrevDayClicked(_ sender: NSButton) {
        let day = sender.tag
        if let prevMonth = cal.date(byAdding: .month, value: -1, to: displayMonth) {
            var comps = cal.dateComponents([.year, .month], from: prevMonth)
            comps.day = day
            if let targetDate = cal.date(from: comps) {
                displayMonth = cal.date(from: cal.dateComponents([.year, .month], from: prevMonth)) ?? prevMonth
                selectedDate = cal.startOfDay(for: targetDate)
                onDateSelected?(selectedDate!)
            }
        }
    }

    @objc private func onNextDayClicked(_ sender: NSButton) {
        let day = sender.tag
        if let nextMonth = cal.date(byAdding: .month, value: 1, to: displayMonth) {
            var comps = cal.dateComponents([.year, .month], from: nextMonth)
            comps.day = day
            if let targetDate = cal.date(from: comps) {
                displayMonth = cal.date(from: cal.dateComponents([.year, .month], from: nextMonth)) ?? nextMonth
                selectedDate = cal.startOfDay(for: targetDate)
                onDateSelected?(selectedDate!)
            }
        }
    }
}
