/*
 * Purpose: Avatar sheet (canvas 7a) — profile header + Edit, Linked accounts,
 *          School (VERIFIED), a master Notifications pill, Sign out, and the
 *          buried "Administer a group" seam. Presented as a glass sheet from the
 *          top-trailing avatar pill (no You tab).
 * Inputs: AvatarSheetViewModel; SessionStore (logout); AppRouter (group seam).
 * Outputs: profile/settings writes; logout; router.go(.community).
 * Run: presented by RootShell via `.sheet(isPresented: $router.avatarSheet)`.
 */

import SwiftUI

struct AvatarSheetView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AvatarSheetViewModel
    @State private var editing = false

    // Injectable VM (default = live). The DEBUG -AvatarSheet hatch injects a
    // fake-backed VM so the standalone screenshot shows the populated 7a persona.
    @MainActor
    init(viewModel: AvatarSheetViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? AvatarSheetViewModel())
    }

    private var initials: String {
        let name = viewModel.profile?.displayName ?? sessionStore.user?.name ?? ""
        let parts = name.split(separator: " ").compactMap(\.first)
        return String(parts.prefix(2)).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(palette.hairline).padding(.vertical, 20)
            row(label: "Linked accounts", badge: viewModel.linkedAccountsLinked ? "LINKED" : nil)
            rowDivider
            row(label: "School", badge: viewModel.schoolVerified ? "VERIFIED" : nil,
                detail: viewModel.profile?.school?.name)
            rowDivider
            notificationsRow
            rowDivider
            signOutRow
            Spacer(minLength: 12)
            administerGroup
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSheet()
        .padding(.horizontal, 14)
        .presentationBackground(.clear)
        .presentationDetents([.large])
        .task { await viewModel.load() }
        .sheet(isPresented: $editing) {
            EditProfileView(viewModel: viewModel)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(palette.ink).frame(width: 52, height: 52)
                Text(initials).font(.archivo(17, weight: 700)).foregroundStyle(palette.onInk)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.profile?.displayName ?? sessionStore.user?.name ?? "")
                    .dsText(.cardTitle).foregroundStyle(palette.ink)
                Text(viewModel.profile?.email ?? sessionStore.user?.email ?? "")
                    .dsText(.meta).foregroundStyle(palette.muted)
            }
            Spacer()
            Button("Edit") { editing = true }
                .font(.archivo(13, weight: 600))
                .foregroundStyle(palette.link)
        }
    }

    private var rowDivider: some View { Divider().overlay(palette.hairlineSoft) }

    private func row(label: String, badge: String?, detail: String? = nil) -> some View {
        HStack {
            Text(label).dsText(.rowTitle).foregroundStyle(palette.ink)
            if let detail { Text(detail).dsText(.meta).foregroundStyle(palette.muted) }
            Spacer()
            if let badge {
                Text(badge).dsText(.kicker).foregroundStyle(palette.green)
            }
        }
        .padding(.vertical, 14)
    }

    private var notificationsRow: some View {
        Toggle(isOn: Binding(
            get: { viewModel.notificationsOn },
            set: { on in Task { await viewModel.setNotifications(on) } }
        )) {
            Text("Notifications").dsText(.rowTitle).foregroundStyle(palette.ink)
        }
        .tint(palette.green)
        .padding(.vertical, 8)
    }

    private var signOutRow: some View {
        Button {
            Task { await sessionStore.logout(); dismiss() }
        } label: {
            Text("Sign out").dsText(.rowTitle).foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 14)
    }

    // Buried, faint, bottom-right — the F8 create-group seam.
    private var administerGroup: some View {
        HStack {
            Spacer()
            Button {
                // F8 seam: replace with the create-group route when FW4 lands.
                AppRouter.shared.go(to: .community)
                dismiss()
            } label: {
                Text("Administer a group").dsText(.meta).foregroundStyle(palette.faint)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct EditProfileView: View {
    @Environment(\.dsPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    let viewModel: AvatarSheetViewModel
    @State private var name = ""
    @State private var bio = ""
    @State private var linkedin = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Display name", text: $name) }
                Section("Bio") { TextField("Bio", text: $bio, axis: .vertical) }
                Section("LinkedIn") { TextField("Profile URL", text: $linkedin).keyboardType(.URL).autocapitalization(.none) }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.saveProfile(displayName: name, bio: bio, linkedinUrl: linkedin); dismiss() }
                    }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear {
                name = viewModel.profile?.displayName ?? ""
                bio = viewModel.profile?.bio ?? ""
                linkedin = viewModel.profile?.linkedinUrl ?? ""
            }
        }
    }
}

#if DEBUG
#Preview {
    ZStack { DSBackground() ; Color.clear }
        .sheet(isPresented: .constant(true)) {
            AvatarSheetView().environment(SessionStore())
        }
}
#endif
