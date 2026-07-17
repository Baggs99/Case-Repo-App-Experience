/*
 * Purpose: Group-create flow (canvas 7a "Administer a group" seam) — a glass
 *          sheet with two states: a name input (one filled ink-capsule
 *          "Create" + underline "Cancel"), then the "YOU'RE THE ADMIN"
 *          success confirmation (group name + invite code, tabular numerals)
 *          with an underline "Done" and an optional filled "Open group" that
 *          pushes straight into the new group's page.
 * Inputs: GroupCreateViewModel (default = live).
 * Outputs: none directly; on "Open group" it drives
 *          AppRouter.shared.communityPath + .selection (the router's public
 *          surface for cross-tab post-create routing — go(to:.groupPage)
 *          only selects the tab, per CaseRoomIntents.swift).
 * Run: presented by RootShell via `.sheet(isPresented: $router.groupCreate)`.
 */

import SwiftUI

struct GroupCreateView: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: GroupCreateViewModel

    // Injectable VM (default = live). The DEBUG -GroupCreateFixtures hatch
    // injects a fixture-backed VM (created pre-populated) so a standalone
    // screenshot shows the populated "YOU'RE THE ADMIN" success state —
    // mirrors AvatarSheetView's `init(viewModel:)` pattern.
    @MainActor
    init(viewModel: GroupCreateViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? GroupCreateViewModel())
    }

    var body: some View {
        Group {
            if viewModel.created != nil {
                successState
            } else {
                inputState
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSheet()
        .padding(.horizontal, 14)
        .presentationBackground(.clear)
        .presentationDetents([.medium])
    }

    // MARK: - Input state

    private var inputState: some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 18) {
            Text("ADMINISTER A GROUP").dsText(.kicker).foregroundStyle(palette.muted)
            Text("Name your group").dsText(.cardTitle).foregroundStyle(palette.ink)

            TextField("Group name", text: $viewModel.name)
                .dsText(.rowTitle).foregroundStyle(palette.ink)
                .padding(.horizontal, 14).padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Rectangle().strokeBorder(palette.hairline, lineWidth: 1)
                )
                .disabled(viewModel.isCreating)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).dsText(.meta).foregroundStyle(palette.muted)
            }

            createButton

            Button { dismiss() } label: {
                Text("Cancel").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
    }

    private var createButton: some View {
        Button {
            Task { await viewModel.create() }
        } label: {
            Text(viewModel.isCreating ? "Creating…" : "Create")
                .dsText(.rowTitle)
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
        .disabled(!viewModel.isNameValid || viewModel.isCreating)
        .opacity(!viewModel.isNameValid || viewModel.isCreating ? 0.5 : 1)
    }

    // MARK: - Success state — verbatim "YOU'RE THE ADMIN"

    private var successState: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("GROUP CREATED").dsText(.kicker).foregroundStyle(palette.green)
            Text("YOU'RE THE ADMIN").dsText(.h1TabSmall).foregroundStyle(palette.ink)
            Text(viewModel.created?.name ?? "").dsText(.rowTitle).foregroundStyle(palette.muted)

            VStack(alignment: .leading, spacing: 4) {
                Text("INVITE CODE").dsText(.kicker).foregroundStyle(palette.muted)
                Text(viewModel.created?.inviteCode ?? "")
                    .font(.archivo(20, weight: 700))
                    .tabularNumbers()
                    .foregroundStyle(palette.ink)
            }
            .padding(.top, 4)

            openGroupButton

            Button { dismiss() } label: {
                Text("Done").dsText(.actionLabel).underline().foregroundStyle(palette.ink)
            }
            .buttonStyle(.plain)
        }
    }

    private var openGroupButton: some View {
        Button {
            guard let id = viewModel.created?.id else { return }
            AppRouter.shared.communityPath.append(.groupPage(id))
            AppRouter.shared.selection = .community
            dismiss()
        } label: {
            Text("Open group")
                .dsText(.rowTitle)
                .foregroundStyle(palette.onInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(DSPressStyle())
        .background(Capsule().fill(palette.ink))
    }
}

#if DEBUG
#Preview("Input") {
    ZStack { DSBackground(); Color.clear }
        .sheet(isPresented: .constant(true)) { GroupCreateView() }
}

#Preview("Success") {
    ZStack { DSBackground(); Color.clear }
        .sheet(isPresented: .constant(true)) {
            GroupCreateView(viewModel: GroupCreateViewModel(fixtureCreated: CommunityFixtures.createdGroup))
        }
}
#endif
