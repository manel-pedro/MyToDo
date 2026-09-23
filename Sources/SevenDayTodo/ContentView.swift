import SwiftUI

struct ContentView: View {
    @Bindable var store: TaskStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seven Day Todo").font(.largeTitle.bold())
                    Text("A clear view of the days around today").foregroundStyle(.secondary)
                }
                Spacer()
                Text(Date.now, format: .dateTime.month(.wide).year())
                    .font(.headline).foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(store.days, id: \.self) { date in
                    DayCard(date: date, items: store.items(for: date), store: store)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 1_080, minHeight: 560, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Couldn’t save your tasks", isPresented: errorIsPresented) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "Unknown error") }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.refreshDays()
            store.reload()
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }
}

private struct DayCard: View {
    let date: Date
    let items: [TodoItem]
    let store: TaskStore
    @State private var newTask = ""

    private var isToday: Bool { Calendar.current.isDateInToday(date) }
    private var isPast: Bool { date < Calendar.current.startOfDay(for: .now) && !isToday }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isToday ? "TODAY" : date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                Text(date.formatted(.dateTime.day().month(.abbreviated))).font(.title2.bold())
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 8) {
                    if items.isEmpty {
                        Text("Nothing planned").font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }
                    ForEach(items) { item in TaskRow(item: item, store: store) }
                }
            }
            Spacer(minLength: 0)
            TextField("Add a task", text: $newTask)
                .textFieldStyle(.plain).padding(9)
                .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                .onSubmit(addTask)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 455, alignment: .top)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isToday ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isToday ? 2 : 1)
        }
        .opacity(isPast ? 0.78 : 1)
        .dropDestination(for: String.self) { values, _ in
            guard let rawID = values.first, let id = UUID(uuidString: rawID) else { return false }
            store.move(itemID: id, to: date)
            return true
        }
    }

    private var cardBackground: Color {
        isToday ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor)
    }

    private func addTask() {
        store.add(title: newTask, to: date)
        newTask = ""
    }
}

private struct TaskRow: View {
    let item: TodoItem
    let store: TaskStore

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button { store.toggle(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            Text(item.title).font(.callout).strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .draggable(item.id.uuidString)
        .contextMenu { Button("Delete", role: .destructive) { store.delete(item) } }
    }
}
