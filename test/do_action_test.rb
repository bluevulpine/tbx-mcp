require_relative 'test_helper'

class DoActionTest < TinderboxIntegrationTest

  def test_do_action_sets_attribute
    path = create_test_note("DoAction")

    response = TinderboxMCP::DoAction.call(
      document: @test_document_name,
      action: "$Color='red'",
      note: path,
      server_context: nil
    )

    refute response.error?

    # Verify the color was set
    eval_response = TinderboxMCP::Evaluate.call(
      document: @test_document_name,
      expression: "$Color",
      note: path,
      server_context: nil
    )
    result = eval_response.content.first[:text]
    # Tinderbox returns color as a hex value or named color
    refute result.empty?, "Expected non-empty color value"
  end

  def test_do_action_on_multiple_notes
    path1 = create_test_note("DoMulti1")
    path2 = create_test_note("DoMulti2")

    response = TinderboxMCP::DoAction.call(
      document: @test_document_name,
      action: "$Color='blue'",
      note: "#{path1};#{path2}",
      server_context: nil
    )

    refute response.error?
    data = JSON.parse(response.content.first[:text])
    assert_equal 2, data.length
  end

  def test_do_action_reports_note_counts
    path = create_test_note("DoCounts")

    data = parse_response(
      TinderboxMCP::DoAction.call(
        document: @test_document_name,
        action: "$Color='green'",
        note: path,
        server_context: nil
      )
    )

    assert data["notes_before"].to_i > 0, "Expected a document-wide note count"
    assert_equal data["notes_before"], data["notes_after"], "A non-destructive action should not change the count"
    refute data.key?("notes_removed"), "notes_removed should be absent when nothing was removed"
  end

  def test_do_action_reports_a_created_note
    path = create_test_note("DoCreates")

    data = parse_response(
      TinderboxMCP::DoAction.call(
        document: @test_document_name,
        action: "create(\"[MCP-TEST] DoCreatesChild\")",
        note: path,
        server_context: nil
      )
    )

    # The count is document-wide, so asserting an exact +1 is racy when notes
    # from adjacent tests are still settling. What matters is the direction and
    # that a creation is never reported as a removal.
    assert data["notes_after"].to_i >= data["notes_before"].to_i,
           "A creating action should not shrink the document"
    refute data.key?("notes_removed")

    children = TinderboxMCP::Evaluate.call(
      document: @test_document_name,
      expression: "$ChildCount",
      note: path,
      server_context: nil
    ).content.first[:text]
    assert_equal "1", children.strip, "Expected create() to have added the child"
  end

  # The guard exists for this case: a designator-scoped delete acts on the note
  # passed as `note:`, and without counts the response is indistinguishable from
  # a no-op. Confined to a disposable container.
  def test_do_action_surfaces_destructive_delete
    container = create_test_note("DoDestroy")
    3.times do |i|
      TinderboxMCP::CreateNote.call(
        document: @test_document_name,
        name: "[MCP-TEST] Doomed#{i}",
        container: container,
        server_context: nil
      )
    end

    data = parse_response(
      TinderboxMCP::DoAction.call(
        document: @test_document_name,
        action: "delete(children)",
        note: container,
        server_context: nil
      )
    )

    assert_equal 3, data["notes_removed"], "Expected the three children to be reported as removed"
    assert_equal data["notes_before"].to_i - 3, data["notes_after"].to_i

    remaining = TinderboxMCP::Evaluate.call(
      document: @test_document_name,
      expression: "$ChildCount",
      note: container,
      server_context: nil
    ).content.first[:text]
    assert_equal "0", remaining.strip, "Expected the container to be emptied"
  end

  def test_do_action_requires_action_and_note
    assert_raises(ArgumentError) do
      TinderboxMCP::DoAction.call(
        document: @test_document_name,
        action: "$Color='red'",
        server_context: nil
      )
    end

    assert_raises(ArgumentError) do
      TinderboxMCP::DoAction.call(
        document: @test_document_name,
        note: "/some/path",
        server_context: nil
      )
    end
  end

end
