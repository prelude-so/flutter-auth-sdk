require 'fileutils'
require 'tmpdir'

# CocoaPods can't resolve apple-auth-sdk (PreludeAuth) or
# apple-sdk (Prelude) transitively from Swift Package Manager, so
# `pod install` vendors them by hand: download the tagged source
# release, copy `Sources/<name>/` under ./sdk/<name>/, stamp a
# `.version` marker, and (for apple-sdk) also fetch the matching
# `PreludeCore.xcframework` binary alongside.
#
# Each tree is managed independently — re-fetching one never
# touches the other — so a version bump on one half doesn't force
# the other to re-download.
#
# Dev escape hatches:
#   - `PRELUDE_AUTH_SDK_LOCAL_PATH` mirrors a local
#     apple-auth-sdk Swift package checkout into
#     `sdk/PreludeAuth/`.
#   - `PRELUDE_SDK_LOCAL_PATH` does the same for apple-sdk's
#     `sdk/Prelude/`. The xcframework still resolves to the
#     pinned binary release; iterating on the C core requires
#     replacing `sdk/core/PreludeCore.xcframework` by hand.

# Helpers live inside a module — `def` at podspec top level is
# evaluated in CocoaPods' own scope (not Object), so methods
# defined there aren't callable from inside `Pod::Spec.new do`.
# Wrapping in a module sidesteps that and keeps the call sites
# clean (`PreludeVendor.foo`).
module PreludeVendor
  module_function

  # Run a shell command, fail loudly with the full command line.
  def run(*argv)
    raise "command failed: #{argv.join(' ')}" unless system(*argv)
  end

  # Return the single non-hidden subdirectory under `dir`. The
  # tagged GitHub archives we extract contain exactly one root
  # (`<repo>-<sha>/`) — anything else is a malformed archive.
  def single_subdir(dir)
    entries = Dir.children(dir)
                  .reject { |e| e.start_with?('.') }
                  .map { |e| File.join(dir, e) }
                  .select { |p| File.directory?(p) }
    unless entries.size == 1
      raise "expected one subdirectory in #{dir}, found #{entries.size}: #{entries.inspect}"
    end
    entries.first
  end

  # Vendor `Sources/<src_subdir>/` from a tagged source archive
  # into `<vendor_dir>/<dest_name>/`.
  #
  # Idempotent: a `.version` marker records the resolved version,
  # so repeat installs short-circuit. Bumping `version` (or the
  # `local_path` env override) invalidates the marker and forces
  # a re-vendor.
  #
  # Yields the source-package root to the optional block while
  # the staging tempdir is still alive — the caller can read
  # sibling files (e.g. `Package.swift`) without re-fetching. The
  # block argument is the local override path on the `local_path`
  # route, the staged extract path on the download route, and
  # `nil` on the cached short-circuit (the caller decides whether
  # to fetch Package.swift on its own).
  def vendor_swift_sources(vendor_dir:, dest_name:, version:, archive_url:, src_subdir:, local_path:)
    target = File.join(vendor_dir, dest_name)
    marker = File.join(target, '.version')

    if local_path && !local_path.empty?
      abs = File.expand_path(local_path)
      src = File.join(abs, 'Sources', src_subdir)
      raise "Local path #{abs} missing Sources/#{src_subdir}/" unless File.directory?(src)
      puts "Mirroring #{dest_name} from local path: #{abs}"
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(vendor_dir)
      FileUtils.cp_r(src, target)
      apply_post_vendor_patches(target, dest_name)
      File.write(marker, "local:#{abs}\n")
      yield abs if block_given?
      return
    end

    expected = "tag:#{version}\n"
    if File.file?(marker) && File.read(marker) == expected
      # Self-heal cached trees: a tree vendored by an earlier
      # podspec rev that didn't run today's fix-ups keeps the
      # original filenames / type names. Re-applying is a no-op
      # once the patches have already landed.
      apply_post_vendor_patches(target, dest_name)
      yield nil if block_given?
      return
    end

    puts "Vendoring #{dest_name} #{version}..."
    Dir.mktmpdir do |staging|
      archive = File.join(staging, 'archive.zip')
      run('curl', '-L', '--fail', '-sS', '-o', archive, archive_url)
      run('unzip', '-q', archive, '-d', staging)
      File.delete(archive)
      source_root = single_subdir(staging)
      src = File.join(source_root, 'Sources', src_subdir)
      raise "#{archive_url}: archive missing Sources/#{src_subdir}/" unless File.directory?(src)
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(vendor_dir)
      FileUtils.cp_r(src, target)
      apply_post_vendor_patches(target, dest_name)
      File.write(marker, expected)
      yield source_root if block_given?
    end
  end

  # Tactical fix-ups applied to a freshly-vendored tree.
  #
  # `Prelude` and `PreludeAuth` are separate SwiftPM modules
  # upstream, but vendoring both into one CocoaPods target merges
  # their namespaces. Until apple-sdk and apple-auth-sdk each
  # publish their own Podspec (so each becomes its own Swift
  # module), we patch the source post-extract to dodge the two
  # known conflicts: a duplicate `Version.swift` filename and a
  # duplicate top-level `Endpoint` type.
  #
  # TODO: drop both patches once the upstream Podspecs ship and
  # this plugin can switch to `s.dependency 'Prelude'` /
  # `s.dependency 'PreludeAuth'`.
  def apply_post_vendor_patches(target, dest_name)
    disambiguate_filenames(target, dest_name)
    patch_type_collisions(target, dest_name)
  end

  # Rename source files whose basename clashes across trees.
  # Xcode rejects two source files with the same basename in one
  # target. Prelude and PreludeAuth both ship a top-level
  # `Version.swift`, so each gets prefixed in its own tree
  # (`<DestName>Version.swift`). The Swift type inside is
  # untouched and the file is referenced only by glob in
  # `s.source_files`, so the rename is invisible to the rest of
  # the build.
  COLLIDING_BASENAMES = %w[Version.swift].freeze

  def disambiguate_filenames(target, dest_name)
    COLLIDING_BASENAMES.each do |basename|
      original = File.join(target, basename)
      next unless File.file?(original)
      renamed = File.join(target, "#{dest_name}#{basename}")
      File.rename(original, renamed)
    end
  end

  # Rename Swift types whose names collide across trees.
  #
  # Keyed by `dest_name`; right side is `original => renamed`.
  # Each rewrite is `\b<original>\b` → `<renamed>`, applied to
  # every `.swift` file in `target`. Idempotent: re-running on
  # an already-patched tree is a no-op because the new name no
  # longer matches the original word boundary.
  #
  # We currently rename only Prelude's `Endpoint` because (a)
  # PreludeAuth references `Endpoint` extensively across its
  # tree while Prelude touches it in one file, and (b) our
  # bridge code uses PreludeAuth's Endpoint, never
  # Prelude's — so the rename is invisible to anything that
  # matters at the call site. If a future apple-sdk release adds
  # another colliding top-level type, extend this table.
  TYPE_RENAMES = {
    'Prelude' => { 'Endpoint' => 'PreludeEndpoint' },
  }.freeze

  def patch_type_collisions(target, dest_name)
    renames = TYPE_RENAMES[dest_name]
    return unless renames
    Dir.glob(File.join(target, '**', '*.swift')).each do |path|
      original_text = File.read(path)
      patched = renames.reduce(original_text) do |text, (from, to)|
        text.gsub(/\b#{Regexp.escape(from)}\b/, to)
      end
      File.write(path, patched) if patched != original_text
    end
  end

  # Vendor `PreludeCore.xcframework` to `<vendor_dir>/core/`.
  #
  # The binary URL lives in apple-sdk's `Package.swift`. When the
  # caller passes a `package_swift_dir` (typical: we just
  # unpacked the source release a moment ago), we read it
  # directly. Otherwise we fetch the apple-sdk source archive on
  # the side just to read `Package.swift` — keeps the source /
  # binary pair in lockstep without a second hard-coded version
  # literal.
  def vendor_prelude_xcframework(vendor_dir:, version:, package_swift_dir:)
    marker = File.join(vendor_dir, 'core', '.version')
    framework = File.join(vendor_dir, 'core', 'PreludeCore.xcframework')
    expected = "tag:#{version}\n"

    return if File.file?(marker) &&
              File.read(marker) == expected &&
              File.directory?(File.join(framework, 'ios-arm64'))

    Dir.mktmpdir do |scratch|
      if package_swift_dir.nil? || !File.file?(File.join(package_swift_dir, 'Package.swift'))
        archive = File.join(scratch, 'apple-sdk.zip')
        run('curl', '-L', '--fail', '-sS', '-o', archive,
            "https://github.com/prelude-so/apple-sdk/archive/refs/tags/#{version}.zip")
        run('unzip', '-q', archive, '-d', scratch)
        File.delete(archive)
        package_swift_dir = single_subdir(scratch)
      end

      package_swift = File.join(package_swift_dir, 'Package.swift')
      match = File.read(package_swift).match(/url:\s*"([^"]*xcframework\.zip)"/)
      raise "Could not find xcframework URL in #{package_swift}" unless match
      xcf_url = match[1]

      puts "Vendoring PreludeCore.xcframework #{version}..."
      xcf_archive = File.join(scratch, 'xcframework.zip')
      run('curl', '-L', '--fail', '-sS', '-o', xcf_archive, xcf_url)
      FileUtils.rm_rf(framework)
      FileUtils.mkdir_p(File.join(vendor_dir, 'core'))
      run('unzip', '-q', xcf_archive, '-d', File.join(vendor_dir, 'core'))
      File.write(marker, expected)
    end
  end
end

Pod::Spec.new do |s|
  s.name             = 'prelude_flutter_auth_sdk'
  s.version          = '0.4.0'
  s.summary          = 'Prelude Flutter Auth SDK.'
  s.description      = <<-DESC
Flutter plugin that bridges Prelude Auth to Flutter applications by
wrapping the native iOS PreludeAuth and Android auth SDKs.
                       DESC
  s.homepage         = 'https://prelude.so/'
  s.license          = 'Apache-2.0'
  s.author           = 'Prelude <hello@prelude.so> (https://github.com/prelude-so)'
  s.source           = { git: 'https://github.com/prelude-so/flutter-auth-sdk.git' }
  s.resource_bundles = {
    'prelude_flutter_auth_sdk_privacy' => [
      'prelude_flutter_auth_sdk/Sources/prelude_flutter_auth_sdk/PrivacyInfo.xcprivacy'
    ]
  }
  s.platforms        = { :ios => '15.1' }
  s.static_framework = true
  s.swift_version    = '5.7'
  s.module_name      = 'prelude_flutter_auth_sdk'

  apple_auth_sdk_version = '0.3.0'
  apple_sdk_version      = '0.5.1'
  vendor_dir = File.join(__dir__, 'sdk')

  PreludeVendor.vendor_swift_sources(
    vendor_dir: vendor_dir,
    dest_name: 'PreludeAuth',
    version: apple_auth_sdk_version,
    archive_url: "https://github.com/prelude-so/apple-auth-sdk/archive/refs/tags/v#{apple_auth_sdk_version}.zip",
    src_subdir: 'PreludeAuth',
    local_path: ENV['PRELUDE_AUTH_SDK_LOCAL_PATH'],
  )

  PreludeVendor.vendor_swift_sources(
    vendor_dir: vendor_dir,
    dest_name: 'Prelude',
    version: apple_sdk_version,
    archive_url: "https://github.com/prelude-so/apple-sdk/archive/refs/tags/#{apple_sdk_version}.zip",
    src_subdir: 'Prelude',
    local_path: ENV['PRELUDE_SDK_LOCAL_PATH'],
  ) do |prelude_source_root|
    # Block runs while the staging tempdir is still alive, so the
    # xcframework hop reads Package.swift in-place — no extra
    # fetch on the fresh-download path.
    PreludeVendor.vendor_prelude_xcframework(
      vendor_dir: vendor_dir,
      version: apple_sdk_version,
      package_swift_dir: prelude_source_root,
    )
  end

  s.dependency 'Flutter'
  s.vendored_frameworks = 'sdk/core/PreludeCore.xcframework'

  s.source_files = [
    'prelude_flutter_auth_sdk/Sources/**/*.swift',
    'sdk/PreludeAuth/**/*.swift',
    'sdk/Prelude/**/*.swift',
  ]

  # Upstream `PreludeSignalsAdapter.swift` ships with `import
  # Prelude` because apple-auth-sdk consumes apple-sdk as a
  # separate SwiftPM module. Under CocoaPods we vendor both
  # source trees into the same pod module, so the import won't
  # resolve. The plugin layer ships its own bridge adapter
  # (`FlutterPreludeSignalsAdapter.swift`) — no `import` needed,
  # types are already in scope.
  s.exclude_files = [
    '**/*.xcprivacy',
    'sdk/PreludeAuth/Signals/PreludeSignalsAdapter.swift',
  ]

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
