//
//  ContextOverlay.swift
//  SidePiece
//

import ComposableArchitecture
import SwiftUI
import UniformTypeIdentifiers

public enum ContextItem: Sendable, Equatable, Identifiable {
    case item(ItemData)
    case container(ContainerData)
    
    public var id: UUID {
        switch self {
        case let .item(data):
            data.id
        case let .container(data):
            data.id
        }
    }
    
    var image: Image {
        switch self {
        case let .item(data):
            data.icon
        case let .container(data):
            data.icon
        }
    }
    
    var title: String {
        switch self {
        case let .item(data):
            data.title
        case let .container(data):
            data.title
        }
    }
    
    var subtitle: String? {
        switch self {
        case let .item(data):
            data.subtitle
        case .container:
            nil
        }
    }
    var underline: Bool {
        switch self {
        case let .item(data):
            data.underline
        case .container:
            false
        }
    }
}

extension ContextItem {
    public enum ItemDataType: Sendable, Equatable {
        case tool
        case file(URL, UTType)
    }
    public struct ItemData: Sendable, Equatable, Identifiable {
        public let id: UUID
        let type: ItemDataType
        let icon: Image
        let title: String
        let subtitle: String?
        let sectionTitle: String?
        let underline: Bool
    }
    
    public struct ContainerData: Sendable, Equatable, Identifiable {
        public let id: UUID
        let icon: Image
        let title: String
        let items: [ContextItem]
    }
}

@Reducer
public struct ContextOverlayFeature: Sendable {
    @ObservableState
    public struct State: Sendable, Equatable {
        var project: URL
        var loading: Bool = true
        var showFilter: Bool = true
        var action: StackState<[ContextItem]> = .init()
        var search: StackState<[ContextItem]> = .init()
        var hovered: ContextItem? = nil
        var selected: ContextItem? = nil
        var filter: String = ""
        var focusTextField: Bool = false
    }
    
    public enum Action: Sendable, Equatable {
        case viewDidAppear
        case back
        case push([ContextItem])
        case select(ContextItem.ItemData)
        case hover(ContextItem?)
        case filter(String)
        case reset
        case `internal`(InternalAction)
        
        @CasePathable
        public enum InternalAction: Equatable, Sendable {
            case performSearch(String)
            case didLoadRecentFiles([ContextItem])
            case didCompleteSearch(String, [ContextItem])
            case up
            case down
        }
    }
    
    @Dependency(\.contextOverlayClient) var client
    @Dependency(\.mainQueue) var mainQueue
    
    enum CancelID {
        case search
    }
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .viewDidAppear:
                state.loading = true
                return .run { [url = state.project] send in
                    let actions = await client.actions(url)
                    await send(.internal(.didLoadRecentFiles(actions)))
                }
            case let .internal(.didLoadRecentFiles(actions)):
                state.action = StackState([actions])
                state.selected = state.action.first?.first
                state.loading = false
                return .none

            case let .internal(.didCompleteSearch(term, items)):
                guard term == state.filter else { return .none }
                state.search = StackState([items])
                state.selected = state.search.first?.first
                return .none
                
            case let .filter(text):
                state.filter = text
                guard !text.isEmpty else {
                    state.selected = state.action.first?.first
                    return .none
                }
                return .send(.internal(.performSearch(text)))
                    .debounce(id: CancelID.search, for: .milliseconds(300), scheduler: mainQueue)

            case .reset:
                state.filter = ""
                state.focusTextField = false
                return .none
            case let .hover(item):
                state.hovered = item
                return .none
            case let .select(data):
                state.selected = .item(data)
                return .none
            case let .push(items):
                state.selected = items.first
                state.action.append(items)
                return .none
            case .back:
                _ = state.action.popLast()
                state.selected = state.action.first?.first
                return .none
            case let .internal(.performSearch(string)):
                return .run { [url = state.project] send in
                    let actions = await client.search(url, string, 10)
                    await send(.internal(.didCompleteSearch(string, actions)))
                }.cancellable(id: CancelID.search, cancelInFlight: true)
            case .internal(.up):
                state.up()
                return .none
            case .internal(.down):
                state.down()
                return .none
            case .internal:
                return .none
            }
        }
    }
}

extension ContextOverlayFeature.State {
    var list: StackState<[ContextItem]> {
        if filter.isEmpty {
            action
        } else {
            search
        }
    }

    mutating func up() {
        guard let list = list.last, !list.isEmpty else { return }
        
        guard let current = selected,
              let currentIndex = list.firstIndex(where: { $0.id == current.id }) else { return }
        let previousIndex = (currentIndex - 1 + list.count) % list.count
        selected = list[previousIndex]
    }

    mutating func down() {
        guard let list = list.last, !list.isEmpty else { return }

        guard let current = selected,
              let currentIndex = list.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = (currentIndex + 1) % list.count
        selected = list[nextIndex]
    }
}

struct ContextOverlayView: View {
    @Bindable var store: StoreOf<ContextOverlayFeature>
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                if store.list.count > 1 {
                    Button {
                        store.send(.back)
                    } label: {
                        Image(systemName: "arrow.left")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if store.showFilter {
                    TextField(
                        "Add files, folders, docs...",
                        text: Binding { store.filter } set: { store.send(.filter($0)) }
                    )
                    .onKeyPress(.upArrow) {
                        store.send(.internal(.up))
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        store.send(.internal(.down))
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        guard let selection = store.selected else { return .ignored }
                        switch selection {
                        case let .container(data):
                            store.send(.push(data.items))
                        case let .item(data):
                            store.send(.select(data))
                        }
                        return .handled
                    }
                    .onKeyPress(.return) {
                        guard let selection = store.selected else { return .ignored }
                        switch selection {
                        case let .container(data):
                            store.send(.push(data.items))
                        case let .item(data):
                            store.send(.select(data))
                        }
                        return .handled
                    }
                    .focused($isTextFieldFocused)
                    .textFieldStyle(.plain)
                    .accentColor(.primary)
                }
            }
            .frame(height: store.showFilter || store.list.count > 1 ? 18 : 0)
            .frame(maxWidth: .infinity)
            .padding(.horizontal)

            if store.loading {
                Spacer()
            } else if let list = store.list.last {
                ScrollViewReader { proxy in
                    List {
                        ForEach(list, id: \.id) { item in
                            Button {
                                switch item {
                                case let .container(data):
                                    store.send(.push(data.items))
                                case let .item(data):
                                    store.send(.select(data))
                                }
                            } label: {
                                HStack {
                                    item.image
                                    Text("\(item.title)")
                                        .lineLimit(1)
                                    Text("\(item.subtitle ?? "")")
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                        .foregroundStyle(.gray)
                                    Spacer()
                                    if case .container = item {
                                        Image(systemName: "chevron.right")
                                    }
                                }
                                .padding(4)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                            }
                            .id(item.id)
                            .listRowSeparator(item.underline ? .visible : .hidden)
                            .listRowInsets(EdgeInsets(
                                top: 2,
                                leading: 0,
                                bottom: 2,
                                trailing: 0
                            ))
                            .buttonStyle(.plain)
                            .onHover { active in
                                store.send(.hover(active ? item : nil))
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        (store.hovered == item) || (store.selected == item) ?
                                        Color.secondary.opacity(0.3) :
                                                .clear
                                    )
                            )
                        }
                    }
                    .environment(\.defaultMinListRowHeight, 0)
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: store.selected?.id) { _, newValue in
                        if let newValue {
                            withAnimation {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding(.top, 8)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.gray, lineWidth: 1)
        )
        .onAppear {
            store.send(.viewDidAppear)
            if store.focusTextField {
                isTextFieldFocused = true
            }
        }
    }
}
