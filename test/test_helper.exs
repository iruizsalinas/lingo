# skip integration tests unless --include integration, ffmpeg tests without
# ffmpeg, and tests across nodes when this node can't be distributed
ffmpeg = if System.find_executable("ffmpeg"), do: [], else: [:ffmpeg]

distributed =
  if Node.alive?() do
    []
  else
    if epmd = System.find_executable("epmd"), do: System.cmd(epmd, ["-daemon"])

    case Node.start(:"lingo_test_#{System.unique_integer([:positive])}", :shortnames) do
      {:ok, _} -> []
      {:error, _} -> [:distributed]
    end
  end

# replies go through tasks and stubbed REST calls, which a loaded machine slows
ExUnit.start(exclude: [:integration] ++ ffmpeg ++ distributed, assert_receive_timeout: 1_000)
