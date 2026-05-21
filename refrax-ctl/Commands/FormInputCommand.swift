import ArgumentParser
import Foundation
import RefraxProtocol

struct FormInputCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "form-input",
        abstract: "Set a form element's value directly",
        discussion: """
        Sets a form element's value without simulating keystrokes. Works with \
        text inputs, textareas, checkboxes, radio buttons, and select elements. \
        Triggers input and change events for framework compatibility.
        
        For checkboxes/radios, use "true"/"false" or "1"/"0".
        For select elements, provide the option value.
        
        Examples:
          refrax-ctl form-input e5 "hello world"
          refrax-ctl form-input e7 "true"
          refrax-ctl form-input e12 "option-value"
          refrax-ctl form-input e5 "hello" --page DEF456
        """,
    )

    @Argument(help: "Element ref ID")
    var ref: String

    @Argument(help: "Value to set")
    var value: String

    @Option(name: .long, help: "Target tab ID")
    var tab: String?

    @Option(name: .long, help: "Page ID (for multi-page tabs)")
    var page: String?

    func run() async throws {
        try sendAndHandle(
            .formInput(.init(ref: ref, value: value, tabID: tab, pageID: page)),
        )
    }
}
