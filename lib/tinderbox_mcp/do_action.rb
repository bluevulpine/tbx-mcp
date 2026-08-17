require "apple_script_helper"
require "json"

module TinderboxMCP

  class DoAction < MCP::Tool

    extend AppleScriptHelper

    tool_name "do"

    description "Perform a Tinderbox action on a Tinderbox note. Reports the document's note count before and after the action, and notes_removed when the count drops, so destructive effects are visible in the response. WARNING: the note parameter is a live target, not just an evaluation context. Designator-scoped verbs act on it — delete(descendants) and delete(children) destroy everything under the note you pass, and delete(this) destroys the note itself. Deletions are not reliably undoable and autosave commits them to disk within seconds. Prefer an explicit path argument over a designator, and prefer moving a note by setting $Container over deleting it."
    input_schema(
      properties: {
        document: {
          type: "string",
          description: "The name of the Tinderbox document"
        },
        action: {
          type: "string",
          description: "A Tinderbox action to perform. Examples: $Color='red', $Badge='flag', createAgent(/path/to/agent)"
        },
        note: {
          type: "string",
          description: "A semicolon-delimited list of one or more names or paths (preferred) of notes on which the action is to be performed."
        }
      },
      required: ["document", "action", "note"]
    )

    DELIM = "%%DELIM%%"

    # Counts every note in the document. `count(all)` and `all.size` do not
    # work here — they return 1 and 3 respectively on a 201-note document.
    COUNT_EXPR = "collect(all,$Path).size".freeze

    def self.call(document:, action:, note:, server_context:)
      note_refs = split_list(note)
      results = []

      note_refs.each do |note_ref|
        # The counts run inside the same osascript invocation as the action.
        # Split across separate invocations this costs ~230% more wall clock;
        # inline it is ~19%, because the process spawn dominates.
        #
        # The "after" count deliberately evaluates against `note 1` rather than
        # noteRef, because the action may have deleted noteRef.
        script = <<~APPLESCRIPT
          tell application id "Cere"
            tell #{doc_target(document)}
              set noteRef to find note in it with path "#{esc(note_ref)}"

              set countBefore to ""
              try
                set countBefore to evaluate noteRef with "#{esc(COUNT_EXPR)}"
              end try

              -- Pass the action string via an AppleScript variable to avoid
              -- double-escaping issues (Tinderbox action code has no quote escaping).
              set actionStr to "#{esc(action)}"
              set actionResult to act on noteRef with actionStr

              -- `act on` may return missing value, which cannot be coerced to
              -- text. Returning it raises -1700, which reads as a failed call
              -- even though the action succeeded.
              if actionResult is missing value then
                set actionResult to ""
              end if

              set countAfter to ""
              try
                set countAfter to evaluate (note 1) with "#{esc(COUNT_EXPR)}"
              end try

              return (actionResult as text) & "#{DELIM}" & countBefore & "#{DELIM}" & countAfter
            end tell
          end tell
        APPLESCRIPT

        raw = run_applescript(script)
        action_result, count_before, count_after = raw.split(DELIM, -1)

        entry = { "note" => note_ref, "result" => action_result.to_s }

        before = count_before.to_s.strip
        after  = count_after.to_s.strip
        unless before.empty? || after.empty?
          entry["notes_before"] = before.to_i
          entry["notes_after"]  = after.to_i
          # Surfaced only when the document shrank — the case worth noticing.
          if after.to_i < before.to_i
            entry["notes_removed"] = before.to_i - after.to_i
          end
        end

        # The delta is document-wide: it reports everything that changed
        # between the two samples, which can include agent, rule, or edict
        # activity rather than this action alone. It is a signal that
        # something was removed, not an audit of what.
        results << entry
      end

      json = results.length == 1 ? JSON.generate(results.first) : JSON.generate(results)
      MCP::Tool::Response.new([{ type: "text", text: json }])
    rescue StandardError => e
      MCP::Tool::Response.new([{ type: "text", text: "Error: #{e.message}" }], error: true)
    end

  end

end
