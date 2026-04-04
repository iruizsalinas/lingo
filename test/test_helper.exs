# load .env.local into System.get_env
if File.exists?(".env.local") do
  ".env.local"
  |> File.read!()
  |> String.split("\n", trim: true)
  |> Enum.each(fn line ->
    line = String.trim(line)

    if line != "" and not String.starts_with?(line, "#") do
      case String.split(line, "=", parts: 2) do
        [key, value] -> System.put_env(String.trim(key), String.trim(value))
        _ -> :ok
      end
    end
  end)
end

# skip integration tests unless --include integration
ExUnit.start(exclude: [:integration])
