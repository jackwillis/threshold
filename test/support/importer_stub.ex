defmodule Threshold.ImporterStub do
  @moduledoc "A fake importer command: `build` writes the fixture's generated files, every command echoes its arguments."

  def command(fixture_generated \\ Path.join([Threshold.World.root(), "tiny", "generated"])) do
    script =
      ~s(if [ "$1" = build ]; then mkdir -p "$4/$2/generated" && cp "#{fixture_generated}"/* "$4/$2/generated/"; fi; echo "$@")

    {"sh", ["-c", script, "--"]}
  end

  def sleeping_command(pid_file) do
    {"sh", ["-c", ~s(echo $$ > "#{pid_file}"; exec sleep 37), "--"]}
  end
end
