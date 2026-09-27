import SwiftUI

/// A multi-line text area that reliably inserts a newline on Return.
///
/// `TextField(axis: .vertical)` can still be pulled into a submit/default action
/// (which ends editing and selects the whole value) when any editing surface in
/// the window has a Return shortcut. `TextEditor` owns Return itself, so note
/// bodies always get a real newline. The placeholder is drawn manually because
/// `TextEditor` has none.
public struct MultilineEditor<Focus: Hashable>: View {
    @Binding private var text: String
    private let placeholder: String
    private let font: Font
    private let minHeight: CGFloat
    private let bordered: Bool
    private let focus: FocusState<Focus?>.Binding
    private let field: Focus

    public init(
        _ placeholder: String,
        text: Binding<String>,
        font: Font = .body,
        minHeight: CGFloat = 64,
        bordered: Bool = false,
        focus: FocusState<Focus?>.Binding,
        field: Focus
    ) {
        self.placeholder = placeholder
        self._text = text
        self.font = font
        self.minHeight = minHeight
        self.bordered = bordered
        self.focus = focus
        self.field = field
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(font)
                .scrollContentBackground(.hidden)
                .focused(focus, equals: field)
        }
        .frame(minHeight: minHeight, alignment: .topLeading)
        .padding(bordered ? 4 : 0)
        .overlay {
            if bordered {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary)
            }
        }
    }
}
