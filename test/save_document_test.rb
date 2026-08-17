require_relative 'test_helper'

class SaveDocumentTest < TinderboxIntegrationTest

  # These tests save the document while test notes exist, which would otherwise
  # persist a [MCP-TEST] note to disk. Save again after cleanup so the on-disk
  # file matches the pre-test state.
  def teardown
    super
    TinderboxMCP::SaveDocument.call(document: @test_document_name, server_context: nil)
  end

  # Read the document's modified flag directly, bypassing our tools.
  def document_modified?
    script = <<~APPLESCRIPT
      tell application id "Cere"
        if modified of document "#{AppleScriptHelper.esc(@test_document_name)}" then
          return "true"
        else
          return "false"
        end if
      end tell
    APPLESCRIPT
    AppleScriptHelper.run_applescript(script) == "true"
  end

  def test_save_returns_expected_fields
    response = TinderboxMCP::SaveDocument.call(
      document: @test_document_name,
      server_context: nil
    )
    result = parse_response(response)

    assert_equal @test_document_name, result["document_name"]
    assert_includes %w[true false], result["was_modified"]
    assert_equal "false", result["still_modified"]
    assert result["file_path"].start_with?("/"), "Expected a POSIX path, got: #{result['file_path']}"
    assert result["file_path"].end_with?(".tbx"), "Expected a .tbx path, got: #{result['file_path']}"
  end

  def test_save_clears_modified_flag
    # Dirty the document by creating a note.
    create_test_note("SaveDirty")
    assert document_modified?, "Expected document to be modified after creating a note"

    response = TinderboxMCP::SaveDocument.call(
      document: @test_document_name,
      server_context: nil
    )
    result = parse_response(response)

    assert_equal "true", result["was_modified"]
    assert_equal "false", result["still_modified"]
    refute document_modified?, "Expected document to be clean after save"
  end

  def test_save_writes_to_disk
    path = TinderboxMCP::SaveDocument.call(
      document: @test_document_name,
      server_context: nil
    ).content.first[:text]
    file_path = JSON.parse(path)["file_path"]

    before = File.mtime(file_path)
    create_test_note("SaveMtime")
    sleep 1 # filesystem mtime granularity

    TinderboxMCP::SaveDocument.call(document: @test_document_name, server_context: nil)

    assert File.mtime(file_path) > before, "Expected the .tbx file mtime to advance after save"
  end

  def test_save_reports_unmodified_document
    # Save twice; the second call should find nothing to commit.
    TinderboxMCP::SaveDocument.call(document: @test_document_name, server_context: nil)

    response = TinderboxMCP::SaveDocument.call(
      document: @test_document_name,
      server_context: nil
    )
    result = parse_response(response)

    assert_equal "false", result["was_modified"]
    assert_equal "false", result["still_modified"]
  end

  def test_save_unknown_document_returns_error
    response = TinderboxMCP::SaveDocument.call(
      document: "No Such Document #{Time.now.to_i}.tbx",
      server_context: nil
    )

    assert response.error?, "Expected an error for an unknown document"
    assert_match(/Error:/, response.content.first[:text])
  end

end
