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

        // Top Month Navigation: [◀]  [October 2026]  [▶]
        let barY = bounds.height - 38
        let prevBtn = NSButton(frame: NSRect(x: 10, y: barY, width: 32, height: 28))
        prevBtn.title = "‹"
        prevBtn.font = NSFont.systemFont(ofSize: 18, weight: .bold)
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
        nextBtn.title = "›"
        nextBtn.font = NSFont.systemFont(ofSize: 18, weight: .bold)
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
        if let prevMonth = cal.date(byAdding: .month, value: -1, to: displayMonth),
           let prevRange = cal.range(of: .day, in: .month, for: prevMonth) {
            let count = prevRange.count
            for d in (count - startCol + 1)...count {
                prevMonthDays.append(d)
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
                        let btn = createDayButton(day: prevMonthDays[cellIndex], frame: cellFrame, isCurrentMonth: false, isToday: false, isSelected: false)
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
                    let btn = createDayButton(day: nextMonthDay, frame: cellFrame, isCurrentMonth: false, isToday: false, isSelected: false)
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
        btn.layer?.cornerRadius = 7

        let centerStyle = NSMutableParagraphStyle()
        centerStyle.alignment = .center

        if isSelected {
            btn.layer?.backgroundColor = NSColor(calibratedRed: 0.92, green: 0.44, blue: 0.16, alpha: 1.0).cgColor
            btn.attributedTitle = NSAttributedString(string: "\(day)", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .heavy),
                .paragraphStyle: centerStyle
            ])
        } else if isToday {
            btn.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1.0).cgColor
            btn.layer?.borderColor = NSColor(calibratedRed: 0.92, green: 0.44, blue: 0.16, alpha: 0.9).cgColor
            btn.layer?.borderWidth = 1.5
            btn.attributedTitle = NSAttributedString(string: "\(day)", attributes: [
                .foregroundColor: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.25, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .paragraphStyle: centerStyle
            ])
        } else if isCurrentMonth {
            btn.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1.0).cgColor
            btn.attributedTitle = NSAttributedString(string: "\(day)", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .paragraphStyle: centerStyle
            ])
        } else {
            btn.layer?.backgroundColor = NSColor.clear.cgColor
            btn.attributedTitle = NSAttributedString(string: "\(day)", attributes: [
                .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0),
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .paragraphStyle: centerStyle
            ])
            btn.isEnabled = false
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
}
