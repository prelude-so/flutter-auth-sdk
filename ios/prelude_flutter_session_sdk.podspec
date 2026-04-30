require 'fileutils'

Pod::Spec.new do |s|
  s.name             = 'prelude_flutter_session_sdk'
  s.version          = '0.2.0'
  s.summary          = 'Prelude Flutter Session SDK.'
  s.description      = <<-DESC
Flutter plugin that bridges Prelude session-based authentication to
Flutter applications by wrapping the native iOS PreludeSession and
Android session SDKs.
                       DESC
  s.homepage         = 'https://prelude.so/'
  s.license          = 'Apache-2.0'
  s.author           = 'Prelude <hello@prelude.so> (https://github.com/prelude-so)'
  s.source           = { git: 'https://github.com/prelude-so/flutter-session-sdk.git' }
  s.resource_bundles = {
    'prelude_flutter_session_sdk_privacy' => [
      'prelude_flutter_session_sdk/Sources/prelude_flutter_session_sdk/PrivacyInfo.xcprivacy'
    ]
  }
  s.platforms        = { :ios => '15.1' }
  s.static_framework = true
  s.swift_version    = '5.7'
  s.module_name      = 'prelude_flutter_session_sdk'

  # Native PreludeSession source resolution.
  #
  # Default: download the pinned `apple_session_sdk_version` of
  # https://github.com/prelude-so/apple-session-sdk and vendor its
  # Sources/PreludeSession/ tree under ./sdk/. PreludeSession is
  # pure Swift, so a single source download is enough — no
  # xcframework, no second curl.
  #
  # Dev escape hatch: `PRELUDE_SESSION_SDK_LOCAL_PATH` (env var) —
  # when set, mirror a local PreludeSession Swift package checkout
  # into ./sdk/ instead of downloading. Resolved relative to this
  # podspec. Useful when iterating on PreludeSession and the bridge
  # in lockstep without cutting an apple-session-sdk release between
  # every change.
  apple_session_sdk_version = '0.1.0'
  vendor_dir = File.join(__dir__, 'sdk')
  vendor_marker = File.join(vendor_dir, 'PreludeSession', '.version')
  local_override = ENV['PRELUDE_SESSION_SDK_LOCAL_PATH']

  if local_override && !local_override.empty?
    abs_local = File.expand_path(local_override, __dir__)
    sources_dir = File.join(abs_local, 'Sources', 'PreludeSession')
    unless File.directory?(sources_dir)
      raise "PRELUDE_SESSION_SDK_LOCAL_PATH=#{abs_local} does not look " \
            'like a PreludeSession Swift package (missing Sources/PreludeSession/).'
    end

    # Mirror the local sources into the pod tree on each install
    # so Xcode picks up edits without a manual sync. Cheap because
    # PreludeSession is pure Swift and small. Stamp a `.version`
    # marker so we can detect "this tree was installed in local
    # mode" on the next install and re-mirror unconditionally.
    FileUtils.rm_rf(vendor_dir)
    FileUtils.mkdir_p(vendor_dir)
    FileUtils.cp_r(sources_dir, vendor_dir)
    File.write(vendor_marker, "local:#{abs_local}\n")
  else
    # Re-use the existing vendored sources iff the marker matches
    # the currently-pinned version. This keeps `pod install` fast
    # for repeat invocations and forces a re-download whenever
    # `apple_session_sdk_version` is bumped.
    expected_marker = "tag:#{apple_session_sdk_version}\n"
    needs_fetch = !File.file?(vendor_marker) || File.read(vendor_marker) != expected_marker

    if needs_fetch
      puts "Prelude Session SDK (PreludeSession) not vendored. " \
           "Downloading version #{apple_session_sdk_version}..."

      download_script = <<-SCRIPT
        set -e
        SDK_VERSION="#{apple_session_sdk_version}"
        VENDOR_DIR="#{vendor_dir}"
        TAG="v$SDK_VERSION"

        rm -rf "$VENDOR_DIR"
        mkdir -p "$VENDOR_DIR"

        echo "Fetching apple-session-sdk $TAG sources..."
        curl -L --fail \
          "https://github.com/prelude-so/apple-session-sdk/archive/refs/tags/$TAG.zip" \
          -o "$VENDOR_DIR/apple-session-sdk.zip"
        unzip -q "$VENDOR_DIR/apple-session-sdk.zip" -d "$VENDOR_DIR/tmp"

        EXTRACTED_DIR=$(ls "$VENDOR_DIR/tmp")
        if [ ! -d "$VENDOR_DIR/tmp/$EXTRACTED_DIR/Sources/PreludeSession" ]; then
          echo "error: extracted archive does not contain Sources/PreludeSession/" >&2
          exit 1
        fi
        mv "$VENDOR_DIR/tmp/$EXTRACTED_DIR/Sources/PreludeSession" "$VENDOR_DIR/PreludeSession"

        rm -rf "$VENDOR_DIR/tmp" "$VENDOR_DIR/apple-session-sdk.zip"
        printf 'tag:%s\n' "$SDK_VERSION" > "$VENDOR_DIR/PreludeSession/.version"

        echo "Prelude Session SDK $SDK_VERSION vendored at $VENDOR_DIR/PreludeSession."
      SCRIPT

      system('/bin/sh', '-c', download_script)

      unless File.file?(vendor_marker) && File.read(vendor_marker) == expected_marker
        raise 'Failed to download Prelude Session SDK. ' \
              "Check connectivity and that v#{apple_session_sdk_version} exists at " \
              'https://github.com/prelude-so/apple-session-sdk/releases.'
      end
    end
  end

  s.dependency 'Flutter'

  s.source_files = [
    'prelude_flutter_session_sdk/Sources/**/*.swift',
    'sdk/PreludeSession/**/*.swift',
  ]

  # `Signals/PreludeSignalsAdapter.swift` imports a module that
  # is not vendored by this plugin. The signals dispatcher
  # protocol stays in scope; only the adapter is excluded.
  s.exclude_files = [
    '**/*.xcprivacy',
    'sdk/PreludeSession/Signals/PreludeSignalsAdapter.swift',
  ]

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
