require "apple_script_helper"
require "json"
require "time"

module TinderboxMCP

  class SaveDocument < MCP::Tool

    extend AppleScriptHelper

    description "Save a Tinderbox document to disk, committing any unsaved changes. Tinderbox does not write changes to disk automatically, so call this after any tool that modifies the document. Confirms the write by comparing the file's modification time on disk before and after saving."
    input_schema(
      properties: {
        document: {
          type: "string",
          description: "The name of the Tinderbox document"
        }
      },
      required: ["document"]
    )

    def self.call(document:, server_context:)
      file_path = resolve_file_path(document)

      before = stat_of(file_path)
      run_applescript(<<~APPLESCRIPT)
        tell application id "Cere"
          save #{doc_target(document)}
        end tell
      APPLESCRIPT
      after = stat_of(file_path)

      # Tinderbox rewrites the file on every save, so an advanced mtime is a
      # reliable confirmation that the save reached disk. The document's own
      # `modified` flag is NOT reliable here — see the note below — so it is
      # deliberately not reported.
      written = after && before && after[:mtime] > before[:mtime]

      result = {
        "document_name" => document,
        "file_path"     => file_path,
        "written"       => !!written,
        "bytes_before"  => before && before[:size],
        "bytes_after"   => after && after[:size],
        "mtime_before"  => before && before[:mtime].utc.iso8601(3),
        "mtime_after"   => after && after[:mtime].utc.iso8601(3),
      }

      unless written
        result["warning"] = "The file's modification time did not advance. The save may not have reached disk; verify the file directly."
      end

      MCP::Tool::Response.new([{ type: "text", text: JSON.generate(result) }])
    rescue StandardError => e
      MCP::Tool::Response.new([{ type: "text", text: "Error: #{e.message}" }], error: true)
    end

    # Resolve the document's on-disk path, refusing documents that have none.
    #
    # A document that has never been saved has no file. Calling `save` on one
    # raises a modal Save As dialog, which blocks osascript indefinitely and
    # would wedge the server — so refuse before saving.
    def self.resolve_file_path(document)
      run_applescript(<<~APPLESCRIPT)
        tell application id "Cere"
          set docRef to #{doc_target(document)}
          set docFile to file of docRef
          if docFile is missing value then
            error "Document \\"#{esc(document)}\\" has never been saved to disk. Save it once manually (Cmd-S) to choose a location, then this tool can save it."
          end if
          return POSIX path of docFile
        end tell
      APPLESCRIPT
    end

    def self.stat_of(path)
      s = File.stat(path)
      { mtime: s.mtime, size: s.size }
    rescue SystemCallError
      nil
    end

    private_class_method :resolve_file_path, :stat_of

  end

end
