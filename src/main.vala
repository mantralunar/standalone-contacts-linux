namespace Contacts {
    class Window : Adw.ApplicationWindow {
        private Store store;
        private Dav dav = new Dav ();
        private GenericArray<Contact> contacts = new GenericArray<Contact> ();
        private Book? book;
        private Contact? selected;
        private bool busy;
        private bool editing;
        private Gtk.StringList book_names = new Gtk.StringList (null);
        private Gtk.DropDown book_menu;
        private Gtk.SearchEntry search = new Gtk.SearchEntry ();
        private Gtk.ListBox list = new Gtk.ListBox ();
        private Gtk.Box details = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        private Gtk.Label status = new Gtk.Label ("");
        private Gtk.Button add_book;
        private Gtk.Button edit_book;
        private Gtk.Button remove_book;
        private Gtk.Button refresh;
        private Gtk.Button create;
        private Gtk.Button import;
        private Gtk.Button export;
        private Gtk.Popover? contact_menu;
        private ulong contact_menu_closed;
        private Adw.ToastOverlay overlay = new Adw.ToastOverlay ();

        public Window (Gtk.Application app, Store store) {
            Object (application: app, title: "Contacts", default_width: 860, default_height: 620);
            this.store = store;

            var toolbar = new Adw.ToolbarView ();
            var header = new Adw.HeaderBar ();
            header.title_widget = new Adw.WindowTitle ("Contacts", "");
            add_book = icon_button ("list-add-symbolic", "Add address book");
            header.pack_start (add_book);
            refresh = icon_button ("view-refresh-symbolic", "Refresh address book");
            header.pack_start (refresh);
            create = new Gtk.Button.with_label ("New Contact");
            create.add_css_class ("suggested-action");
            header.pack_end (create);
            toolbar.add_top_bar (header);

            var root = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var split = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            split.vexpand = true;
            split.position = 290;
            split.shrink_start_child = false;
            split.shrink_end_child = false;

            var sidebar = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            sidebar.width_request = 230;
            sidebar.add_css_class ("sidebar");
            book_menu = new Gtk.DropDown (book_names, null);
            book_menu.tooltip_text = "Address book";
            book_menu.margin_top = 10;
            book_menu.margin_start = book_menu.margin_end = 10;
            var chooser = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
            chooser.margin_top = 10;
            chooser.margin_start = chooser.margin_end = 10;
            book_menu.margin_top = book_menu.margin_start = book_menu.margin_end = 0;
            book_menu.hexpand = true;
            chooser.append (book_menu);
            edit_book = icon_button ("document-edit-symbolic", "Edit address book");
            remove_book = icon_button ("list-remove-symbolic", "Remove address book");
            chooser.append (edit_book);
            chooser.append (remove_book);
            sidebar.append (chooser);
            search.placeholder_text = "Search contacts";
            search.margin_start = search.margin_end = 10;
            sidebar.append (search);
            list.selection_mode = Gtk.SelectionMode.MULTIPLE;
            // GTK's single-click activation bypasses the modifier-aware selection path.
            list.activate_on_single_click = false;
            list.add_css_class ("navigation-sidebar");
            list.set_filter_func ((row) => {
                var contact_row = row as ContactRow;
                return contact_row != null && contact_row.index_text.contains (search.text.casefold ());
            });
            var list_scroll = new Gtk.ScrolledWindow ();
            list_scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            list_scroll.vexpand = true;
            list_scroll.child = list;
            sidebar.append (list_scroll);
            var transfer = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            transfer.margin_bottom = 8;
            transfer.margin_start = transfer.margin_end = 10;
            import = new Gtk.Button.with_label ("Import");
            export = new Gtk.Button.with_label ("Export");
            transfer.append (import);
            transfer.append (export);
            sidebar.append (transfer);
            split.start_child = sidebar;

            var scroll = new Gtk.ScrolledWindow ();
            scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
            var clamp = new Adw.Clamp ();
            clamp.maximum_size = 580;
            details.margin_top = 28;
            details.margin_bottom = 24;
            details.margin_start = details.margin_end = 18;
            clamp.child = details;
            scroll.child = clamp;
            split.end_child = scroll;
            root.append (split);
            status.margin_top = status.margin_bottom = 6;
            status.margin_start = status.margin_end = 12;
            status.xalign = 0;
            status.ellipsize = Pango.EllipsizeMode.END;
            status.add_css_class ("dim-label");
            root.append (new Gtk.Separator (Gtk.Orientation.HORIZONTAL));
            root.append (status);
            overlay.child = root;
            toolbar.content = overlay;
            content = toolbar;

            foreach (Book item in store.books) book_names.append (item.label);
            book_menu.notify["selected"].connect (select_book);
            add_book.clicked.connect (() => book_dialog (null));
            edit_book.clicked.connect (() => book_dialog (book));
            remove_book.clicked.connect (remove_book_dialog);
            refresh.clicked.connect (() => refresh_current.begin ());
            create.clicked.connect (() => {
                list.unselect_all ();
                start_editing ();
            });
            import.clicked.connect (() => import_file.begin ());
            export.clicked.connect (() => export_file.begin ());
            search.search_changed.connect (() => {
                close_contact_menu ();
                list.unselect_all ();
                list.invalidate_filter ();
            });
            list.selected_rows_changed.connect (update_selection);
            add_contact_menu_controls ();
            close_request.connect (() => {
                close_contact_menu ();
                return false;
            });
            select_book ();
        }

        private Gtk.Button icon_button (string icon, string label) {
            var button = new Gtk.Button.from_icon_name (icon);
            button.tooltip_text = label;
            button.update_property (Gtk.AccessibleProperty.LABEL, label, -1);
            return button;
        }

        private void notice (string message) {
            overlay.add_toast (new Adw.Toast (message));
        }

        private void update_controls () {
            bool browsing = !busy && !editing;
            add_book.sensitive = browsing;
            edit_book.sensitive = browsing && book != null;
            remove_book.sensitive = browsing && book != null;
            book_menu.sensitive = browsing && store.books.length > 0;
            refresh.sensitive = browsing && book != null;
            create.sensitive = browsing && book != null;
            import.sensitive = browsing && book != null;
            export.sensitive = browsing && contacts.length > 0;
            list.sensitive = !editing;
            search.sensitive = !editing;
            details.sensitive = !busy;
        }

        private void select_book () {
            uint index = book_menu.selected;
            book = index < (uint) store.books.length ? store.books[index] : null;
            contacts = new GenericArray<Contact> ();
            status.label = "Add an address book to get started.";
            if (book != null) {
                try {
                    contacts = store.load (book);
                    status.label = "%u cached contacts · Refresh to sync".printf (contacts.length);
                } catch (Error error) {
                    status.label = error.message;
                }
            }
            render ();
        }

        private GenericArray<Contact> selected_contacts () {
            var selection = new GenericArray<Contact> ();
            foreach (Gtk.ListBoxRow row in list.get_selected_rows ()) {
                var contact_row = row as ContactRow;
                if (contact_row != null && row.get_child_visible ())
                    selection.add (contact_row.contact);
            }
            return selection;
        }

        private void update_selection () {
            if (editing) return;
            var selection = selected_contacts ();
            selected = selection.length == 1 ? selection[0] : null;
            show_details (selection.length);
        }

        private void render (string? keep = null) {
            close_contact_menu ();
            Gtk.Widget? child;
            while ((child = list.get_first_child ()) != null) list.remove (child);
            contacts.sort ((a, b) => a.card.name.casefold ().collate (b.card.name.casefold ()));
            ContactRow? keep_row = null;
            foreach (Contact contact in contacts) {
                var row = new ContactRow (contact);
                list.append (row);
                if (contact.url == keep) keep_row = row;
            }
            if (keep_row != null) list.select_row (keep_row);
            update_selection ();
            update_controls ();
        }

        private void show_details (int selection_count = 0) {
            Gtk.Widget? child;
            while ((child = details.get_first_child ()) != null) details.remove (child);
            var contact = selected;
            if (editing) {
                show_editor (contact);
                return;
            }
            if (contact == null) {
                var page = new Adw.StatusPage ();
                page.icon_name = "avatar-default-symbolic";
                page.title = selection_count > 1 ? "%d contacts selected".printf (selection_count)
                    : (book == null ? "No Address Book" : "Select a Contact");
                page.description = book == null ? "Add your CardDAV address book to see your contacts." : null;
                details.append (page);
                return;
            }
            string name = contact.card.name;
            details.append (contact_avatar (contact, 96));
            var title = new Gtk.Label (name == "" ? "Unnamed contact" : name);
            title.wrap = true;
            title.selectable = true;
            title.add_css_class ("title-1");
            details.append (title);
            var group = new Adw.PreferencesGroup ();
            add_field (group, "Email", contact.card.read ("EMAIL"));
            add_field (group, "Phone", contact.card.read ("TEL"));
            add_field (group, "Organisation", contact.card.read ("ORG"));
            add_field (group, "Notes", contact.card.read ("NOTE"));
            details.append (group);
            var edit = new Gtk.Button.with_label ("Edit");
            edit.halign = Gtk.Align.CENTER;
            edit.clicked.connect (start_editing);
            details.append (edit);
        }

        private void add_contact_menu_controls () {
            var click = new Gtk.GestureClick ();
            click.button = Gdk.BUTTON_SECONDARY;
            click.pressed.connect ((count, x, y) => {
                if (count != 1 || busy || editing) return;
                var row = list.get_row_at_y ((int) y) as ContactRow;
                if (row == null) return;
                Graphene.Point point = { (float) x, (float) y };
                Graphene.Point anchor;
                if (list.compute_point (row, point, out anchor))
                    show_contact_menu (row, (int) anchor.x, (int) anchor.y);
            });
            list.add_controller (click);

            var keys = new Gtk.EventControllerKey ();
            keys.key_pressed.connect ((key, code, modifiers) => {
                if (busy || editing ||
                    (key != Gdk.Key.Menu && !(key == Gdk.Key.F10 &&
                        (modifiers & Gdk.ModifierType.SHIFT_MASK) != 0))) return false;
                var row = list.get_focus_child () as ContactRow;
                if (row == null) return false;
                show_contact_menu (row, row.get_width () / 2, row.get_height () / 2);
                return true;
            });
            list.add_controller (keys);
        }

        private void show_contact_menu (ContactRow row, int x, int y) {
            close_contact_menu ();
            if (!row.is_selected ()) {
                list.unselect_all ();
                list.select_row (row);
            }
            var selection = selected_contacts ();
            if (selection.length == 0) return;
            var entries = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            var export_item = new Gtk.Button.with_label (selection.length == 1
                ? "Export Contact…" : "Export %d Contacts…".printf (selection.length));
            export_item.halign = Gtk.Align.FILL;
            export_item.add_css_class ("flat");
            export_item.clicked.connect (() => {
                close_contact_menu ();
                export_file.begin (selection);
            });
            entries.append (export_item);

            var delete_item = new Gtk.Button.with_label (selection.length == 1
                ? "Delete Contact…" : "Delete %d Contacts…".printf (selection.length));
            delete_item.halign = Gtk.Align.FILL;
            delete_item.add_css_class ("flat");
            delete_item.clicked.connect (() => {
                close_contact_menu ();
                delete_dialog (selection);
            });
            entries.append (delete_item);

            var menu = new Gtk.Popover ();
            menu.child = entries;
            menu.set_parent (row);
            Gdk.Rectangle location = { x, y, 1, 1 };
            menu.set_pointing_to (location);
            menu.has_arrow = false;
            contact_menu = menu;
            contact_menu_closed = menu.closed.connect (close_contact_menu);
            menu.popup ();
        }

        private void close_contact_menu () {
            var menu = contact_menu;
            if (menu == null) return;
            contact_menu = null;
            SignalHandler.disconnect (menu, contact_menu_closed);
            menu.popdown ();
            menu.unparent ();
        }

        private void add_field (Adw.PreferencesGroup group, string title, string text) {
            if (text == "") return;
            var row = new Adw.ActionRow ();
            row.title = title;
            var value = new Gtk.Label (text);
            value.wrap = true;
            value.selectable = true;
            value.xalign = 0;
            value.max_width_chars = 42;
            row.add_suffix (value);
            group.add (row);
        }

        private Gtk.Entry input (Gtk.Box box, string label, bool secret = false) {
            var caption = new Gtk.Label (label);
            caption.xalign = 0;
            box.append (caption);
            var entry = new Gtk.Entry ();
            entry.visibility = !secret;
            entry.activates_default = true;
            box.append (entry);
            return entry;
        }

        private Gtk.Box form () {
            var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            return box;
        }

        private void book_dialog (Book? existing) {
            if (busy) return;
            var dialog = new Adw.MessageDialog (this,
                existing == null ? "Add Address Book" : "Edit Address Book",
                existing == null
                    ? "Find books using your server URL, or enter a full collection URL and save directly."
                    : "Leave the app token blank to keep the current token for this account.");
            var box = form ();
            var label = input (box, "Address book name");
            var url = input (box, "CardDAV server or collection URL");
            var user = input (box, "Username");
            var token = input (box, "App token", true);
            if (existing != null) {
                label.text = existing.label;
                url.text = existing.url;
                user.text = existing.user;
            }
            dialog.extra_child = box;
            dialog.add_response ("cancel", "Cancel");
            if (existing == null) dialog.add_response ("discover", "Find Books");
            dialog.add_response ("save", "Save");
            string primary = existing == null ? "discover" : "save";
            dialog.default_response = primary;
            dialog.set_response_appearance (primary, Adw.ResponseAppearance.SUGGESTED);
            dialog.response.connect ((answer) => {
                if (answer == "cancel") return;
                string password = token.text;
                token.text = "";
                if (answer == "discover")
                    discover_books.begin (url.text, user.text, password);
                else if (answer == "save")
                    save_address_book.begin (existing, label.text, url.text, user.text, password);
            });
            dialog.present ();
        }

        private async void discover_books (string url, string username, string token) {
            if (busy) return;
            busy = true;
            update_controls ();
            try {
                string user = username.strip ();
                if (user == "" || user.contains (":") || token == "")
                    throw new Failure.INVALID ("Enter a username and app token.");
                var account = new Book ("", "", Dav.book_url (url), user);
                var found = yield dav.discover (account, token);
                var dialog = new Adw.MessageDialog (this, "Choose an Address Book", null);
                var names = new Gtk.StringList (null);
                foreach (Book result in found) names.append (result.label + " · " + result.url);
                var choices = new Gtk.DropDown (names, null);
                dialog.extra_child = choices;
                dialog.add_response ("cancel", "Cancel");
                dialog.add_response ("add", "Add");
                dialog.default_response = "add";
                dialog.set_response_appearance ("add", Adw.ResponseAppearance.SUGGESTED);
                dialog.response.connect ((answer) => {
                    uint index = choices.selected;
                    if (answer == "add" && index < (uint) found.length) {
                        var item = found[index];
                        save_address_book.begin (null, item.label, item.url, item.user, token);
                    }
                });
                dialog.present ();
            } catch (Error error) { notice (error.message); }
            busy = false;
            update_controls ();
        }

        private void refresh_books (Book? preferred) {
            var names = new Gtk.StringList (null);
            uint selection = 0;
            for (uint i = 0; i < (uint) store.books.length; i++) {
                var item = store.books[i];
                names.append (item.label);
                if (item == preferred) selection = i;
            }
            book_names = names;
            book_menu.model = book_names;
            book_menu.selected = selection;
            select_book ();
        }

        private async void save_address_book (Book? previous, string label, string url,
            string username, string token) {
            if (busy) return;
            busy = true;
            update_controls ();
            Book? item = null;
            try {
                string user = username.strip ();
                if (label.strip () == "" || user == "" || user.contains (":"))
                    throw new Failure.INVALID ("Enter an address book name and username.");
                string endpoint = Dav.book_url (url);
                bool same_account = previous != null && previous.url == endpoint && previous.user == user;
                if (!same_account && token == "")
                    throw new Failure.INVALID ("Enter the app token for this address book URL and username.");
                string id = same_account && token == "" && previous != null
                    ? previous.id : Uuid.string_random ();
                item = new Book (id, label.strip (), endpoint, user);
                yield store.save_book (item, previous, token == "" ? null : token);
                refresh_books (item);
                notice ("Address book saved.");
            } catch (Error error) {
                bool saved = item != null && store.books.find (item);
                if (saved) refresh_books (item);
                notice (saved ? "Address book saved. Local cleanup failed: " + error.message : error.message);
            }
            busy = false;
            update_controls ();
        }

        private void remove_book_dialog () {
            var item = book;
            if (busy || item == null) return;
            var dialog = new Adw.MessageDialog (this, "Remove Address Book?",
                "This removes the saved account, token and cached contacts from this app. The contacts on the server stay available.");
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("remove", "Remove");
            dialog.set_response_appearance ("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((answer) => {
                if (answer == "remove") remove_address_book.begin (item);
            });
            dialog.present ();
        }

        private async void remove_address_book (Book item) {
            if (busy) return;
            busy = true;
            update_controls ();
            try {
                yield store.remove_book (item);
                notice ("Address book removed.");
            } catch (Error error) {
                bool removed = !store.books.find (item);
                notice (removed ? "Address book removed. Local cleanup failed: " + error.message : error.message);
            }
            refresh_books (item);
            busy = false;
            update_controls ();
        }

        private async void reload (Book current, string token, string? keep = null) throws Error {
            var next = yield dav.pull (current, token, contacts);
            store.save (current, next);
            contacts = next;
            status.label = "%u contacts · Refreshed".printf (contacts.length);
            render (keep);
        }

        private async void refresh_current () {
            var current = book;
            if (busy || current == null) return;
            string? keep = selected != null ? selected.url : null;
            busy = true;
            update_controls ();
            status.label = "Refreshing address book…";
            try {
                string token = yield store.token (current);
                yield reload (current, token, keep);
            } catch (Error error) {
                status.label = "%u cached contacts · Refresh failed".printf (contacts.length);
                notice (error.message);
            }
            busy = false;
            update_controls ();
        }

        private void start_editing () {
            close_contact_menu ();
            editing = true;
            show_details ();
            update_controls ();
        }

        private Adw.EntryRow editor_field (Adw.PreferencesGroup group, string title, string value) {
            var field = new Adw.EntryRow ();
            field.title = title;
            field.text = value;
            group.add (field);
            return field;
        }

        private void show_editor (Contact? contact) {
            var card = contact != null ? contact.card : null;
            if (contact != null) details.append (contact_avatar (contact, 96));
            var group = new Adw.PreferencesGroup ();
            var name = editor_field (group, "Name", card != null ? card.name : "");
            var email = editor_field (group, "Email", card != null ? card.read ("EMAIL") : "");
            var phone = editor_field (group, "Phone", card != null ? card.read ("TEL") : "");
            var org = editor_field (group, "Organisation", card != null ? card.read ("ORG") : "");
            details.append (group);

            var notes_label = new Gtk.Label ("Notes");
            notes_label.xalign = 0;
            notes_label.add_css_class ("heading");
            details.append (notes_label);
            var notes = new Gtk.TextView ();
            notes.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            notes.update_property (Gtk.AccessibleProperty.LABEL, "Notes", -1);
            notes.buffer.text = card != null ? card.read ("NOTE") : "";
            var scroll = new Gtk.ScrolledWindow ();
            scroll.min_content_height = 100;
            scroll.has_frame = true;
            scroll.child = notes;
            details.append (scroll);

            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.halign = Gtk.Align.END;
            var cancel = new Gtk.Button.with_label ("Cancel");
            cancel.clicked.connect (finish_editing);
            actions.append (cancel);
            var save = new Gtk.Button.with_label ("Save");
            save.add_css_class ("suggested-action");
            save.clicked.connect (() => {
                try {
                    var original = card ?? VCard.create (name.text, Uuid.string_random ());
                    var updated = original.edit (name.text, email.text, phone.text, org.text,
                        notes.buffer.text);
                    save_card.begin (contact, updated);
                } catch (Error error) { notice (error.message); }
            });
            actions.append (save);
            details.append (actions);
            name.grab_focus ();
        }

        private void finish_editing () {
            editing = false;
            show_details ();
            update_controls ();
        }

        private void delete_dialog (GenericArray<Contact> selection) {
            int count = selection.length;
            var dialog = new Adw.MessageDialog (this,
                count == 1 ? "Delete Contact?" : "Delete %d Contacts?".printf (count),
                "This removes the selected contacts from the server address book.");
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("delete", "Delete");
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((answer) => {
                if (answer == "delete") delete_contacts.begin (selection);
            });
            dialog.present ();
        }

        private async void delete_contacts (GenericArray<Contact> selection) {
            var current = book;
            if (busy || current == null) return;
            busy = true;
            update_controls ();
            var removed = new GenericArray<Contact> ();
            status.label = selection.length == 1 ? "Deleting contact…"
                : "Deleting %d contacts…".printf (selection.length);
            try {
                string token = yield store.token (current);
                Error? deletion_error = null;
                foreach (Contact contact in selection) {
                    try {
                        yield dav.remove (current, token, contact);
                        removed.add (contact);
                    } catch (Error error) {
                        deletion_error = error;
                        break;
                    }
                }
                if (removed.length > 0) {
                    // Only remove rows whose DELETE succeeded, even if the refresh fails.
                    foreach (Contact contact in removed) contacts.remove (contact);
                    render ();
                    try { yield reload (current, token); }
                    catch (Error error) {
                        status.label = "Contacts deleted. Refresh failed.";
                        try { store.save (current, contacts); }
                        catch (Error cache_error) {
                            status.label = "Contacts deleted. The offline cache could not be updated.";
                        }
                        if (deletion_error == null) throw error;
                    }
                }
                if (deletion_error != null) throw deletion_error;
                notice (removed.length == 1 ? "Contact deleted."
                    : "%d contacts deleted.".printf (removed.length));
            } catch (Error error) {
                if (removed.length == 0) status.label = "Delete failed.";
                notice (removed.length == 0 ? error.message
                    : "%d of %d contacts deleted. %s".printf (removed.length, selection.length, error.message));
            }
            busy = false;
            update_controls ();
        }

        private async void save_card (Contact? contact, VCard card) {
            var current = book;
            if (busy || current == null) return;
            if (contact != null && contact.card.raw == card.raw) {
                finish_editing ();
                return;
            }
            busy = true;
            update_controls ();
            string url = contact != null ? contact.url : current.url + Uuid.string_random () + ".vcf";
            bool sent = false;
            try {
                string token = yield store.token (current);
                yield dav.put (current, token, url, contact != null ? contact.etag : null, card);
                sent = true;
                finish_editing ();
                yield reload (current, token, url);
            } catch (Error error) {
                notice (sent ? "Saved on server. Refresh failed: " + error.message : error.message);
            }
            busy = false;
            update_controls ();
        }

        private async void import_file () {
            var current = book;
            if (busy || current == null) return;
            busy = true;
            update_controls ();
            uint imported = 0;
            try {
                var picker = new Gtk.FileDialog ();
                picker.title = "Import vCards";
                File file = yield picker.open (this, null);
                uint8[] bytes;
                yield file.load_contents_async (null, out bytes, null);
                foreach (uint8 value in bytes) {
                    if (value == 0) throw new Failure.INVALID ("The vCard file contains a NUL byte.");
                }
                var cards = VCard.parse_file ((string) bytes);
                string token = yield store.token (current);
                Error? upload_error = null;
                foreach (VCard card in cards) {
                    try {
                        yield dav.put (current, token, current.url + Uuid.string_random () + ".vcf", null, card);
                        imported++;
                    } catch (Error error) {
                        upload_error = error;
                        break;
                    }
                }
                if (imported > 0) yield reload (current, token);
                if (upload_error != null) throw upload_error;
                notice ("%u contacts imported.".printf (imported));
            } catch (Error error) {
                if (!(error is Gtk.DialogError.DISMISSED))
                    notice (imported == 0 ? error.message : "%u uploaded. %s".printf (imported, error.message));
            }
            busy = false;
            update_controls ();
        }

        private async void export_file (GenericArray<Contact>? selection = null) {
            if (busy) return;
            var output = new StringBuilder ();
            foreach (Contact entry in (selection ?? contacts)) {
                if (output.len > 0 && !output.str.has_suffix ("\n")) output.append ("\r\n");
                output.append (entry.card.raw);
            }
            try {
                var picker = new Gtk.FileDialog ();
                picker.title = "Export vCards";
                picker.initial_name = selection != null && selection.length == 1 ? "contact.vcf" : "contacts.vcf";
                File file = yield picker.save (this, null);
                yield file.replace_contents_bytes_async (new Bytes (output.str.data), null, false,
                    FileCreateFlags.PRIVATE | FileCreateFlags.REPLACE_DESTINATION, null, null);
                notice ("Exported vCards.");
            } catch (Error error) {
                if (!(error is Gtk.DialogError.DISMISSED)) notice (error.message);
            }
        }
    }

    Adw.Avatar contact_avatar (Contact contact, int size) {
        var avatar = new Adw.Avatar (size, contact.card.name, true);
        var photo = contact.card.photo ();
        if (photo != null) {
            try { avatar.custom_image = Gdk.Texture.from_bytes (photo); }
            catch (Error ignored) {}
        }
        return avatar;
    }

    class ContactRow : Gtk.ListBoxRow {
        public Contact contact;
        public string index_text;
        public ContactRow (Contact contact) {
            this.contact = contact;
            string name = contact.card.name;
            index_text = (name + " " + contact.card.read ("EMAIL") + " "
                + contact.card.read ("TEL")).casefold ();
            var line = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            line.margin_top = line.margin_bottom = 4;
            line.append (contact_avatar (contact, 34));
            var label = new Gtk.Label (name == "" ? "Unnamed contact" : name);
            label.ellipsize = Pango.EllipsizeMode.END;
            label.xalign = 0;
            line.append (label);
            child = line;
        }
    }

    class Application : Adw.Application {
        public bool smoke;
        public bool failed;
        public Application (bool smoke) {
            Object (application_id: "io.github.StandaloneContacts",
                flags: smoke ? ApplicationFlags.NON_UNIQUE : ApplicationFlags.DEFAULT_FLAGS);
            this.smoke = smoke;
        }

        protected override void activate () {
            if (active_window != null) {
                active_window.present ();
                return;
            }
            try {
                if (smoke && !TlsBackend.get_default ().supports_tls ())
                    throw new Failure.INVALID ("The GIO TLS backend is missing.");
                var window = new Window (this, new Store ());
                window.present ();
                if (smoke) Timeout.add (350, () => {
                    failed = !window.get_mapped ();
                    quit ();
                    return Source.REMOVE;
                });
            } catch (Error error) {
                stderr.printf ("%s\n", error.message);
                failed = true;
                quit ();
            }
        }
    }

    int main (string[] args) {
        if (args.length == 2 && args[1] == "--version") {
            stdout.printf ("Contacts 0.3.4\n");
            return 0;
        }
        bool smoke = args.length == 2 && args[1] == "--smoke-test";
        var app = new Application (smoke);
        int result = app.run (smoke ? new string[] { args[0] } : args);
        return app.failed ? 1 : result;
    }
}
