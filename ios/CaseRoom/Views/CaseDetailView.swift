/*
 * Purpose: Case detail screen — metadata header, horizontal preview strip,
 *          and a PDF ShareLink, loaded via CasesService.caseDetail(id:).
 * Inputs: caseId; CasesService (default APIClient.shared).
 * Outputs: none.
 * Run: pushed from CasesListView on row tap.
 */

import SwiftUI

struct CaseDetailView: View {
    let caseId: Int
    private let service: CasesService

    @State private var detail: CaseDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(caseId: Int, service: CasesService = APIClient.shared) {
        self.caseId = caseId
        self.service = service
    }

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(for: detail)
                        previews(for: detail)
                    }
                    .padding()
                }
                .toolbar {
                    if let pdfURL = APIClient.shared.resolveURL(detail.pdfUrl) {
                        ToolbarItem(placement: .topBarTrailing) {
                            ShareLink(item: pdfURL)
                        }
                    }
                }
            } else if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(errorMessage, systemImage: "wifi.slash")
            }
        }
        .navigationTitle(detail?.caseTitle ?? "Case")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await service.caseDetail(id: caseId)
        } catch {
            errorMessage = "Couldn't load this case. Try again."
        }
    }

    @ViewBuilder
    private func header(for detail: CaseDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.caseTitle)
                .font(.title2.bold())

            if let difficulty = detail.difficulty {
                Text(difficulty)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color("BrandAccent").opacity(0.15))
                    .foregroundStyle(Color("BrandAccent"))
                    .clipShape(Capsule())
            }

            if let industry = detail.industryDisplay {
                Label(industry, systemImage: "building.2")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let firm = detail.firm {
                Label(firm, systemImage: "briefcase")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let schoolYear = schoolYearLine(for: detail) {
                Label(schoolYear, systemImage: "graduationcap")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func schoolYearLine(for detail: CaseDetail) -> String? {
        switch (detail.sourceSchool, detail.sourceYear) {
        case let (school?, year?): return "\(school) · \(String(year))"
        case let (school?, nil): return school
        case let (nil, year?): return String(year)
        default: return nil
        }
    }

    @ViewBuilder
    private func previews(for detail: CaseDetail) -> some View {
        if !detail.previewUrls.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(detail.previewUrls, id: \.self) { path in
                        if let url = APIClient.shared.resolveURL(path) {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fit)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(width: 200, height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CaseDetailView(caseId: 1)
    }
}
