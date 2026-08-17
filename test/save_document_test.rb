require_relative 'test_helper'

class SaveDocumentTest < TinderboxIntegrationTest

  # These tests save the document while test notes exist, which would otherwise
  # persist a [MCP-TEST] note to disk. Save again after cleanup so the on-disk
  # file matches the pre-test state.
  def teardown
    super
    TinderboxMCP::SaveDocument.call(document: @test_document_name, server_context: nil)
  end

  def save
    parse_response(
      TinderboxMCP::SaveDocument.call(document: @test_document_name, server_context: nil)
    )
  end

  def test_save_returns_expected_fields
    result = save

    assert_equal @test_document_name, result["document_name"]
    assert result["file_path"].start_with?("/"), "Expected a POSIX path, got: #{result['file_path']}"
    assert result["file_path"].end_with?(".tbx"), "Expected a .tbx path, got: #{result['file_path']}"
    assert result["bytes_after"].to_i > 0, "Expected a non-empty file"
    refute_nil result["mtime_after"]
  end

  # The document's `modified` flag is unreliable (agents and rules re-dirty the
  # document asynchronously), so saving is verified against the filesystem.
  def test_save_writes_to_disk
    file_path = save["file_path"]

    create_test_note("SaveMtime")
    before = File.mtime(file_path)
    sleep 1 # filesystem mtime granularity

    result = save

    assert_equal true, result["written"], "Expected the save to be confirmed as written"
    assert File.mtime(file_path) > before, "Expected the .tbx file mtime to advance after save"
    refute result.key?("warning"), "Unexpected warning: #{result['warning']}"
  end

  # Tinderbox rewrites the file on every save, even with no pending changes,
  # so back-to-back saves should both report a confirmed write.
  def test_consecutive_saves_both_confirm_write
    save
    sleep 1
    result = save

    assert_equal true, result["written"], "Expected an unconditional rewrite on save"
  end

  def test_save_persists_note_text_to_disk
    path = create_test_note("SavePersist")
    marker = "MCPTESTMARKER#{Time.now.to_i}#{rand(10_000)}"

    TinderboxMCP::SetValue.call(
      document: @test_document_name,
      notes: path,
      attribute: "Text",
      value: "Persisted marker #{marker}.",
      server_context: nil
    )

    file_path = save["file_path"]

    assert File.read(file_path, mode: "rb").include?(marker),
           "Expected the saved .tbx file to contain the marker text written before saving"
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
