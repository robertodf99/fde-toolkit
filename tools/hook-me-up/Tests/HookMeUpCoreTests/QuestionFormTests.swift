import Foundation
import Testing

@testable import HookMeUpCore

/// An AskUserQuestion tool_input as Claude Code sends it (two questions, one multi-select).
private let e4Input: JSONValue = {
    let json = #"""
        {"questions":[{"question":"Which of these two colours do you prefer?","header":"Colour","options":[{"label":"Blue","description":"A calm, cool colour."},{"label":"Orange","description":"A warm, energetic colour."}],"multiSelect":false},{"question":"Which of these colours do you like? Select as many as you want.","header":"Likes","options":[{"label":"Blue","description":"Cool and calm."},{"label":"Orange","description":"Warm and energetic."},{"label":"Green","description":"Fresh and natural."},{"label":"Purple","description":"Rich and bold."}],"multiSelect":true}]}
        """#
    return try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}()
private let q1 = "Which of these two colours do you prefer?"
private let q2 = "Which of these colours do you like? Select as many as you want."

@Suite struct QuestionFormTests {
    @Test func parsesRealAskUserQuestionInput() throws {
        let form = try #require(QuestionForm(toolInput: e4Input))
        #expect(form.questions.count == 2)
        #expect(
            form.questions[0]
                == QuestionForm.Question(
                    text: q1, header: "Colour",
                    options: [
                        .init(label: "Blue", description: "A calm, cool colour."),
                        .init(label: "Orange", description: "A warm, energetic colour."),
                    ],
                    multiSelect: false))
        #expect(form.questions[1].multiSelect)
        #expect(form.questions[1].text == q2)
        #expect(form.questions[1].options.map(\.label) == ["Blue", "Orange", "Green", "Purple"])
    }

    @Test func optionsWithoutALabelAreSkipped() throws {
        let input: JSONValue = .object([
            "questions": .array([
                .object([
                    "question": "Pick one",
                    "options": .array([
                        .object(["label": ""]), .object(["description": "no label"]),
                        .object(["label": "Yes"]),
                    ]),
                ])
            ])
        ])
        let form = try #require(QuestionForm(toolInput: input))
        #expect(form.questions[0].options.map(\.label) == ["Yes"])
        #expect(!form.questions[0].multiSelect)
    }

    @Test(arguments: [
        nil, JSONValue.object([:]), .object(["questions": .array([])]),
        .object(["questions": .array([.object(["header": "no text"])])]),
    ])
    func invalidInputGivesNoForm(_ input: JSONValue?) {
        #expect(QuestionForm(toolInput: input) == nil)
    }

    @Test func repeatedQuestionTextsGiveNoForm() {
        let repeated: JSONValue = .object([
            "questions": .array([
                .object(["question": "Which?", "options": .array([.object(["label": "A"])])]),
                .object(["question": "Which?", "options": .array([.object(["label": "B"])])]),
            ])
        ])
        #expect(QuestionForm(toolInput: repeated) == nil)
    }
}
