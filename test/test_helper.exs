# skip integration tests unless --include integration, and ffmpeg tests without ffmpeg
ffmpeg = if System.find_executable("ffmpeg"), do: [], else: [:ffmpeg]
ExUnit.start(exclude: [:integration | ffmpeg])
