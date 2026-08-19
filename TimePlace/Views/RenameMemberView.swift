import SwiftUI

struct RenameMemberView: View {

    @Environment(\.dismiss) private var dismiss

    @State private var name: String

    let onSave: (String) -> Void

    init(
        currentName: String,
        onSave: @escaping (String) -> Void
    ) {
        _name = State(initialValue: currentName)
        self.onSave = onSave
    }

    var body: some View {

        NavigationStack {

            Form {

                Section("Name") {

                    TextField(
                        "Name",
                        text: $name
                    )
                }

                Section {

                    Text(
                        "This name is only visible to you."
                    )
                    .font(.caption)
                    .foregroundColor(.gray)
                }
            }

            .navigationTitle("Change Name")
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {

                ToolbarItem(
                    placement: .cancellationAction
                ) {

                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(
                    placement: .confirmationAction
                ) {

                    Button("Save") {

                        onSave(
                            name.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                        )

                        dismiss()
                    }
                }
            }
        }
    }
}