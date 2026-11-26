namespace Contacts {
    class Window : Adw.ApplicationWindow {
        private Store store;
        private Dav dav = new Dav ();
        private GenericArray<Contact> contacts = new GenericArray<Contact> ();
        private Book? book;
        private Contact? selected;
        private bool busy;
        private Gtk.StringList book_names = new Gtk.StringList (null);
        private Gtk.DropDown book_menu;
        private Gtk.SearchEntry search = new Gtk.SearchEntry ();
        private Gtk.ListBox list = new Gtk.ListBox ();
        private Gtk.Box details = new Gtk.Box (Gtk.Orientation.VERTICAL, 12);
        private Gtk.Label status = new Gtk.Label ("");
        private Gtk.Button add_book;
        private Gtk.Button refresh;
        private Gtk.Button create;
        private Gtk.Button import;
        private Gtk.Button export;
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
            sidebar.append (book_menu);
            search.placeholder_text = "Search contacts";
            search.margin_start = search.margin_end = 10;
            sidebar.append (search);
            list.selection_mode = Gtk.SelectionMode.SINGLE;
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
            add_book.clicked.connect (book_dialog);
            refresh.clicked.connect (() => refresh_current.begin ());
            create.clicked.connect (() => name_dialog (null));
            import.clicked.connect (() => import_file.begin ());
            export.clicked.connect (() => export_file.begin ());
            search.search_changed.connect (() => list.invalidate_filter ());
            list.row_selected.connect ((row) => {
                var contact_row = row as ContactRow;
                selected = contact_row != null ? contact_row.contact : null;
                show_details ();
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
            add_book.sensitive = !busy;
            book_menu.sensitive = !busy && store.books.length > 0;
            refresh.sensitive = !busy && book != null;
            create.sensitive = !busy && book != null;
            import.sensitive = !busy && book != null;
            export.sensitive = !busy && contacts.length > 0;
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

        private void render (string? keep = null) {
            Gtk.Widget? child;
            while ((child = list.get_first_child ()) != null) list.remove (child);
            contacts.sort ((a, b) => a.card.name.casefold ().collate (b.card.name.casefold ()));
            ContactRow? keep_row = null;
            foreach (Contact contact in contacts) {
                var row = new ContactRow (contact);
                list.append (row);
                if (contact.url == keep) keep_row = row;
            }
            selected = null;
            if (keep_row != null) list.select_row (keep_row);
            show_details ();
            update_controls ();
        }

        private void show_details () {
            Gtk.Widget? child;
            while ((child = details.get_first_child ()) != null) details.remove (child);
            var contact = selected;
            if (contact == null) {
                var page = new Adw.StatusPage ();
                page.icon_name = "avatar-default-symbolic";
                page.title = book == null ? "No Address Book" : "Select a Contact";
                page.description = book == null ? "Add your CardDAV address book to see your contacts." : null;
                details.append (page);
                return;
            }
            string name = contact.card.name;
            var avatar = new Adw.Avatar (96, name, true);
            var photo = contact.card.photo ();
            if (photo != null) {
                try { avatar.custom_image = Gdk.Texture.from_bytes (photo); }
                catch (Error ignored) {}
            }
            details.append (avatar);
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
            var actions = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            actions.halign = Gtk.Align.CENTER;
            var edit = new Gtk.Button.with_label ("Edit vCard");
            edit.clicked.connect (() => edit_dialog (contact));
            actions.append (edit);
            var save = new Gtk.Button.with_label ("Export Contact");
            save.clicked.connect (() => export_file.begin (contact));
            actions.append (save);
            var remove = new Gtk.Button.with_label ("Delete");
            remove.add_css_class ("destructive-action");
            remove.clicked.connect (() => delete_dialog (contact));
            actions.append (remove);
            details.append (actions);
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

        private void book_dialog () {
            if (busy) return;
            var dialog = new Adw.MessageDialog (this, "Add Address Book",
                "Use the full CardDAV address book URL and the app token for your account.");
            var box = form ();
            var label = input (box, "Address book name");
            var url = input (box, "CardDAV address book URL");
            var user = input (box, "Username");
            var token = input (box, "App token", true);
            dialog.extra_child = box;
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("add", "Add");
            dialog.default_response = "add";
            dialog.set_response_appearance ("add", Adw.ResponseAppearance.SUGGESTED);
            dialog.response.connect ((answer) => {
                if (answer != "add") return;
                string password = token.text;
                token.text = "";
                add_address_book.begin (label.text, url.text, user.text, password);
            });
            dialog.present ();
        }

        private async void add_address_book (string label, string url, string user, string token) {
            if (busy) return;
            busy = true;
            update_controls ();
            try {
                if (label.strip () == "" || user.strip () == "" || user.contains (":") || token == "")
                    throw new Failure.INVALID ("Enter a name, username and app token.");
                var item = new Book (Uuid.string_random (), label.strip (), Dav.book_url (url), user.strip ());
                yield store.add (item, token);
                book_names.append (item.label);
                book_menu.selected = (uint) (store.books.length - 1);
                if (book != item) select_book ();
                status.label = "Address book saved. Refresh to connect.";
            } catch (Error error) { notice (error.message); }
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

        private void name_dialog (Contact? contact) {
            var dialog = new Adw.MessageDialog (this,
                contact == null ? "New Contact" : "Display Name", null);
            var box = form ();
            var name = input (box, "Name");
            if (contact != null) name.text = contact.card.name;
            dialog.extra_child = box;
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("save", "Save");
            dialog.default_response = "save";
            dialog.response.connect ((answer) => {
                if (answer != "save") return;
                try {
                    if (name.text.strip () == "") throw new Failure.INVALID ("Enter a display name.");
                    save_card.begin (contact, contact != null
                        ? contact.card.rename (name.text) : VCard.create (name.text, Uuid.string_random ()));
                } catch (Error error) { notice (error.message); }
            });
            dialog.present ();
        }

        private void edit_dialog (Contact contact) {
            var dialog = new Adw.MessageDialog (this, "Edit vCard",
                "Edit the original vCard fields. Keep the UID and card markers.");
            var box = form ();
            var name_button = new Gtk.Button.with_label ("Edit Display Name Only");
            name_button.clicked.connect (() => {
                dialog.close ();
                name_dialog (contact);
            });
            box.append (name_button);
            var view = new Gtk.TextView ();
            view.monospace = true;
            view.buffer.text = contact.card.raw;
            var scroll = new Gtk.ScrolledWindow ();
            scroll.min_content_height = 260;
            scroll.min_content_width = 360;
            scroll.child = view;
            box.append (scroll);
            dialog.extra_child = box;
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("save", "Save");
            dialog.set_response_appearance ("save", Adw.ResponseAppearance.SUGGESTED);
            dialog.response.connect ((answer) => {
                if (answer != "save") return;
                try {
                    var cards = VCard.parse_file (view.buffer.text);
                    if (cards.length != 1 || cards[0].read ("UID") != contact.card.read ("UID"))
                        throw new Failure.INVALID ("Keep exactly one vCard with its original UID.");
                    save_card.begin (contact, cards[0]);
                } catch (Error error) { notice (error.message); }
            });
            dialog.present ();
        }

        private void delete_dialog (Contact contact) {
            var dialog = new Adw.MessageDialog (this, "Delete Contact?",
                "This removes the contact from the server address book.");
            dialog.add_response ("cancel", "Cancel");
            dialog.add_response ("delete", "Delete");
            dialog.set_response_appearance ("delete", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.response.connect ((answer) => { if (answer == "delete") delete_card.begin (contact); });
            dialog.present ();
        }

        private async void delete_card (Contact contact) {
            var current = book;
            if (busy || current == null) return;
            busy = true;
            update_controls ();
            bool sent = false;
            try {
                string token = yield store.token (current);
                yield dav.remove (current, token, contact);
                sent = true;
                yield reload (current, token);
            } catch (Error error) {
                notice (sent ? "Deleted on server. Refresh failed: " + error.message : error.message);
            }
            busy = false;
            update_controls ();
        }

        private async void save_card (Contact? contact, VCard card) {
            var current = book;
            if (busy || current == null) return;
            if (contact != null && contact.card.raw == card.raw) return;
            busy = true;
            update_controls ();
            string url = contact != null ? contact.url : current.url + Uuid.string_random () + ".vcf";
            bool sent = false;
            try {
                string token = yield store.token (current);
                yield dav.put (current, token, url, contact != null ? contact.etag : null, card);
                sent = true;
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

        private async void export_file (Contact? contact = null) {
            if (busy) return;
            var output = new StringBuilder ();
            if (contact != null) output.append (contact.card.raw);
            else foreach (Contact entry in contacts) {
                if (output.len > 0 && !output.str.has_suffix ("\n")) output.append ("\r\n");
                output.append (entry.card.raw);
            }
            try {
                var picker = new Gtk.FileDialog ();
                picker.title = "Export vCards";
                picker.initial_name = contact == null ? "contacts.vcf" : "contact.vcf";
                File file = yield picker.save (this, null);
                yield file.replace_contents_bytes_async (new Bytes (output.str.data), null, false,
                    FileCreateFlags.PRIVATE | FileCreateFlags.REPLACE_DESTINATION, null, null);
                notice ("Exported vCards.");
            } catch (Error error) {
                if (!(error is Gtk.DialogError.DISMISSED)) notice (error.message);
            }
        }
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
            line.append (new Adw.Avatar (34, name, true));
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
            stdout.printf ("Standalone Contacts 0.1.0\n");
            return 0;
        }
        bool smoke = args.length == 2 && args[1] == "--smoke-test";
        var app = new Application (smoke);
        int result = app.run (smoke ? new string[] { args[0] } : args);
        return app.failed ? 1 : result;
    }
}
