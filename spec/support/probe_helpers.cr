def run_crig_probe(source : String) : JSON::Any
  probe_id = "#{Process.pid}_#{Time.utc.to_unix_ms}_#{Random.rand(1_000_000)}"
  source_path = nil.as(String?)
  binary_path = nil.as(String?)
  cache_dir = "#{Dir.current}/temp/crystal-cache"
  Dir.mkdir_p(cache_dir)
  env = {"CRYSTAL_CACHE_DIR" => cache_dir}

  source_path = "#{Dir.current}/.crig_probe_#{probe_id}.cr"
  binary_path = "#{cache_dir}/crig_probe_#{probe_id}"
  File.write(source_path, source)

  build_output = IO::Memory.new
  build_error = IO::Memory.new
  build_status = Process.run(
    "crystal",
    ["build", source_path, "-o", binary_path],
    chdir: Dir.current,
    env: env,
    output: build_output,
    error: build_error,
  )
  unless build_status.success?
    stderr = build_error.to_s
    stdout = build_output.to_s
    raise "crig probe build failed: #{stderr.empty? ? stdout : stderr}"
  end

  run_output = IO::Memory.new
  run_error = IO::Memory.new
  run_status = Process.run(
    binary_path,
    chdir: Dir.current,
    env: env,
    output: run_output,
    error: run_error,
  )

  return JSON.parse(run_output.to_s) if run_status.success?

  stderr = run_error.to_s
  stdout = run_output.to_s
  raise "crig probe failed: #{stderr.empty? ? stdout : stderr}"
ensure
  if path = source_path
    File.delete(path) if File.exists?(path)
  end
  if path = binary_path
    File.delete(path) if File.exists?(path)
  end
end
