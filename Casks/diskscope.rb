cask "diskscope" do
  version "1.1.1"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/fso13/DiskScope/releases/download/v#{version}/DiskScope-#{version}-macos-universal.dmg"
  name "DiskScope"
  desc "Local disk space analyzer and cleanup assistant"
  homepage "https://github.com/fso13/DiskScope"

  depends_on macos: ">= :sonoma"

  app "DiskScope.app"

  uninstall quit: "ru.diskscope.app"

  zap trash: [
    "~/Library/Application Support/DiskScope",
    "~/Library/Preferences/ru.diskscope.app.plist",
  ]
end
