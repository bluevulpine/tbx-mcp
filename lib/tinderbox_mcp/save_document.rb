require "apple_script_helper"

module TinderboxMCP

  class SaveDocument < MCP::Tool

    extend AppleScriptHelper

    description "Save a Tinderbox document to disk, committing any unsaved changes. Tinderbox does not write changes to disk automatically, so call this after any tool that modifies the document."
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
      # A document that has never been saved has no file on disk. Calling
      # `save` on one raises a modal Save As dialog, which blocks osascript
      # indefinitely and wedges the server — so refuse before saving.
      script = <<~APPLESCRIPT
        #{script_functions}

        tell application id "Cere"
          set docRef to #{doc_target(document)}
          set docFile to file of docRef

          if docFile is missing value then
            error "Document \\"#{esc(document)}\\" has never been saved to disk. Save it once manually (Cmd-S) to choose a location, then this tool can save it."
          end if

          set filePath to POSIX path of docFile

          if modified of docRef then
            set wasModified to "true"
          else
            set wasModified to "false"
          end if

          save docRef

          if modified of docRef then
            set stillModified to "true"
          else
            set stillModified to "false"
          end if

          return my toJSON({document_name:(name of docRef), was_modified:wasModified, still_modified:stillModified, file_path:filePath})
        end tell
      APPLESCRIPT

      result = run_applescript(script)
      MCP::Tool::Response.new([{ type: "text", text: result }])
    rescue StandardError => e
      MCP::Tool::Response.new([{ type: "text", text: "Error: #{e.message}" }], error: true)
    end

  end

end
