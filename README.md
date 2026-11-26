# Standalone Contacts

A desktop CardDAV client written in Vala with GTK4, libadwaita, libsoup 3 and libsecret. The two-pane interface follows the system light or dark preference. It works directly with CardDAV and has no Evolution Data Server or GNOME Online Accounts dependency.

## Publish an AppImage

1. Extract the source archive and upload its **contents** to the root of an empty GitHub repository. Include the hidden `.github` directory. Git push is the simplest way to include hidden files.
2. Once the workflow is on the default branch, open **Actions → Anylinux AppImage Release → Run workflow**, select `main`, and click **Run workflow**. The workflow uses the version in `meson.build` and creates the matching tag for that commit if needed. Pushing a matching tag such as `v0.2.0` also starts the workflow. Bump the Meson version before releasing a different commit.

   GitHub Actions builds and tests the app on x86_64 using pkgforge's Arch Linux container, the Anylinux setup action, and quick-sharun. The AppImage uses GTK’s Cairo renderer and omits bundled Mesa drivers. After the AppImage passes its startup check, the workflow publishes it under **Releases → v0.2.0 → Assets**.
3. Download `Standalone-Contacts-0.2.0-x86_64.AppImage` from the release. Make it executable and run it:

   ```sh
   chmod +x Standalone-Contacts-0.2.0-x86_64.AppImage
   ./Standalone-Contacts-0.2.0-x86_64.AppImage
   ```

   If FUSE mounting fails, run it with `APPIMAGE_EXTRACT_AND_RUN=1`.

See [pkgforge’s Anylinux guide](https://github.com/pkgforge-dev/Anylinux-AppImages/blob/main/HOW-TO-MAKE-THESE.md) for the packaging tools.

## Connect an address book

Choose **Add Address Book**, enter your HTTPS server URL, username and app token, then click **Find Books**. On OpenCloud with Radicale, you can also start with `https://your-cloud.example/carddav/`. Select a discovered book and click **Add**. For manual setup, enter a label and the full address book collection URL, then click **Save**. Add each collection separately. Click **Refresh** to fetch contacts.

Use the edit button next to the address book selector to change the label, URL, username, or token. Enter a new token when changing the URL or username. Use the remove button to delete the saved book, its cached contacts, and its keyring entry from the app. The server collection and its contents stay available.

The system Secret Service stores tokens. The cache under `$XDG_DATA_HOME/standalone-contacts/` (usually `~/.local/share/standalone-contacts/`) contains book metadata and vCards in private local files. Cached contacts can be searched, viewed and exported while offline. The cache contains readable contact data and relies on the permissions and encryption of your local storage.

Use **Edit vCard** to change the source card or select **Edit Display Name Only** to update its display name while retaining the original bytes of other lines. The UI previews the first email, phone, organisation and note. Embedded base64 photos are shown when GTK can decode them. **Export** saves the selected book; **Export Contact** saves the displayed contact. **Import** parses one or more cards, then uploads the original card data. If an upload fails partway through, it reports the number already uploaded.

## Sync and MVP limits

- Refresh uses a depth-1 PROPFIND. It reuses cards with unchanged strong ETags and only replaces the local snapshot after a complete successful download and atomic cache write.
- Editing and deleting require the cached strong ETag in `If-Match`. New resources use `If-None-Match: *`. HTTP 412 leaves the cached copy intact. Refresh and review the server copy before retrying. A successful write followed by a failed refresh is reported separately.
- Use the real, final collection URL. The client accepts HTTPS and permits HTTP for loopback testing. Discovery supports same-origin redirects and reads CardDAV principal and address book home properties. It does not use DNS SRV discovery. Synchronisation rejects redirects and limits resource URLs to the configured collection. Server TLS certificates must be trusted by the system.
- Sync is manual. The MVP has no offline write queue, duplicate merging, or conflict merge editor. Each configured collection has its own keyring item and cache.
- Input must be UTF-8 with LF or CRLF line endings. Legacy vCard encodings and external photo URLs are preserved as source text where accepted but are not decoded. The raw editor exposes the original fields. A server may normalize uploaded cards, so later downloads can reflect server-side changes.
- GitHub Actions is configured to run vCard round-trip and local HTTP CardDAV discovery and conditional-request tests and to launch the generated AppImage under Xvfb, including a check for the GIO TLS backend. The discovery and address book management changes need a GitHub build and runtime verification. Live OpenCloud, Radicale, desktop keyring interoperability, and compatibility across distributions remain unverified. AppImage size will be known after packaging.
