# Standalone Contacts

A desktop CardDAV client written in Vala with GTK4, libadwaita, libsoup 3 and libsecret. The two-pane interface follows the system light or dark preference. It works directly with CardDAV and has no Evolution Data Server or GNOME Online Accounts dependency.

## Publish an AppImage

1. Extract the source archive and upload its **contents** to the root of an empty GitHub repository. Include the hidden `.github` directory. Git push is the simplest way to include hidden files.
2. Push a version tag matching the version in `meson.build`. For the first release:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

   GitHub Actions builds and tests the app on x86_64 using pkgforge's Arch Linux container, the Anylinux setup action, and quick-sharun. After the AppImage passes its startup check, the workflow publishes it under **Releases → v0.1.0 → Assets**.
3. Download `Standalone-Contacts-0.1.0-x86_64.AppImage` from the release. Make it executable and run it:

   ```sh
   chmod +x Standalone-Contacts-0.1.0-x86_64.AppImage
   ./Standalone-Contacts-0.1.0-x86_64.AppImage
   ```

   If FUSE mounting fails, run it with `APPIMAGE_EXTRACT_AND_RUN=1`.

See [pkgforge’s Anylinux guide](https://github.com/pkgforge-dev/Anylinux-AppImages/blob/main/HOW-TO-MAKE-THESE.md) for the packaging tools.

## Connect an address book

Choose **Add Address Book**, then supply a label, the complete CardDAV collection URL, your username, and the app token or password accepted for HTTP Basic authentication by your server. Use the specific collection shown by your server or reverse proxy, ending in a slash. Add each collection separately, including additional collections on the same account. Click **Refresh** to fetch contacts.

The system Secret Service stores tokens. The cache under `$XDG_DATA_HOME/standalone-contacts/` (usually `~/.local/share/standalone-contacts/`) contains book metadata and vCards in private local files. Cached contacts can be searched, viewed and exported while offline. The cache contains readable contact data and relies on the permissions and encryption of your local storage.

Use **Edit vCard** to change the source card or select **Edit Display Name Only** to update its display name while retaining the original bytes of other lines. The UI previews the first email, phone, organisation and note. Embedded base64 photos are shown when GTK can decode them. **Export** saves the selected book; **Export Contact** saves the displayed contact. **Import** parses one or more cards, then uploads the original card data. If an upload fails partway through, it reports the number already uploaded.

## Sync and MVP limits

- Refresh uses a depth-1 PROPFIND. It reuses cards with unchanged strong ETags and only replaces the local snapshot after a complete successful download and atomic cache write.
- Editing and deleting require the cached strong ETag in `If-Match`. New resources use `If-None-Match: *`. HTTP 412 leaves the cached copy intact. Refresh and review the server copy before retrying. A successful write followed by a failed refresh is reported separately.
- Use the real, final collection URL. The client accepts HTTPS and permits HTTP for loopback testing. It does not follow redirects or send credentials to resource URLs outside the configured collection. Server TLS certificates must be trusted by the system.
- Sync is manual. The MVP has no account discovery, token rotation or account removal in the UI, offline write queue, duplicate merging, or conflict merge editor. Each configured collection has its own keyring item and cache.
- Input must be UTF-8 with LF or CRLF line endings. Legacy vCard encodings and external photo URLs are preserved as source text where accepted but are not decoded. The raw editor exposes the original fields. A server may normalize uploaded cards, so later downloads can reflect server-side changes.
- GitHub Actions is configured to run vCard round-trip and local HTTP CardDAV tests and to launch the generated AppImage under Xvfb, including a check for the GIO TLS backend. The first GitHub run is pending. Live OpenCloud, Radicale, desktop keyring interoperability, and compatibility across distributions remain unverified. AppImage size will be known after packaging.
