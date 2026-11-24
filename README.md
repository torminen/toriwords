# ToriWords
ToriWords is a native iOS and Android app for building a personal vocabulary and mastering words and phrases through spaced repetition.

## Build the iOS app

These steps build ToriWords for your own iPhone with a free Apple ID. No paid developer account is needed. This build
has no iCloud sync, Share sheet or widget. Words, review, speech, translation and the offline dictionary all work.

You need a Mac with Xcode 27, [Homebrew](https://brew.sh), an Apple ID, and an iPhone on iOS 18 or later. You can
also use the iOS Simulator.

1. **Clone the repo.**

   ```sh
   git clone https://github.com/torminen/toriwords.git
   cd toriwords
   ```

2. **Install Tuist**, which generates the Xcode project. Use the pinned version:

   ```sh
   brew install mise
   echo 'eval "$(mise activate zsh)"' >> ~/.zshrc && source ~/.zshrc
   mise use -g tuist@$(cat ios/.tuist-version)
   ```

3. **Download the dictionary**, about 60 MB. It is a prebuilt file from GitHub Releases, so nothing is built
   locally. Without it, the app falls back to a small sample of a few hundred words.

   ```sh
   tools/dictionary/fetch.sh
   ```

4. **Sign in to Xcode.** In Xcode → Settings → Accounts, add your Apple ID. This creates a free "Personal Team".

5. **Set up signing.** Copy the template:

   ```sh
   cp ios/Config/Personal.local.xcconfig.example ios/Config/Personal.local.xcconfig
   ```

   In the copy, set the following:
   - `DEVELOPMENT_TEAM`: your Personal Team ID.
   - `TORI_BUNDLE_ID`: any unique ID, for example `com.yourname.toriwords`.

   The copy is gitignored.

6. **Generate the project.** Xcode opens the workspace when this finishes:

   ```sh
   cd ios
   tuist install
   tuist generate
   ```

7. **Run the app.** In Xcode, select the **`Toriwords-Personal`** scheme. Pick your iPhone or a simulator, then
   press Run (⌘R).

8. **First install on an iPhone only:**
   - Turn on Settings → Privacy & Security → Developer Mode.
   - After the install, trust your profile in Settings → General → VPN & Device Management.

   With a free Apple ID, the app stops opening after 7 days. Run it from Xcode again to reinstall it.

For the architecture, tests, the full iCloud build and the configuration reference, see [ios/README.md](ios/README.md).

## License

Source code is licensed under the [Apache License 2.0](LICENSE).

The ToriWords name, logo and app icon are not covered by this license
and may not be used to publish derivative apps without permission.
