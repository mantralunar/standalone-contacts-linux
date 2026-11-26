namespace Contacts {
    class Book : Object {
        public string id;
        public string label;
        public string url;
        public string user;
        public Book (string id, string label, string url, string user) {
            this.id = id;
            this.label = label;
            this.url = url;
            this.user = user;
        }
    }

    class Contact : Object {
        public string url;
        public string etag;
        public VCard card;
        public Contact (string url, string etag, VCard card) {
            this.url = url;
            this.etag = etag;
            this.card = card;
        }
    }

    class Store : Object {
        private string root;
        public GenericArray<Book> books = new GenericArray<Book> ();
        private Secret.Schema token_schema = new Secret.Schema (
            "io.github.StandaloneContacts.Token", Secret.SchemaFlags.NONE,
            "book", Secret.SchemaAttributeType.STRING, null);

        public Store () throws Error {
            root = Path.build_filename (Environment.get_user_data_dir (), "standalone-contacts");
            if (DirUtils.create_with_parents (root, 0700) != 0)
                throw new Failure.STORAGE ("Cannot create the contacts data directory.");
            var config = new KeyFile ();
            string file = Path.build_filename (root, "books.ini");
            if (!FileUtils.test (file, FileTest.EXISTS)) return;
            config.load_from_file (file, KeyFileFlags.NONE);
            foreach (string id in config.get_groups ()) {
                if (!Uuid.string_is_valid (id))
                    throw new Failure.STORAGE ("Invalid address book identifier.");
                books.add (new Book (id, config.get_string (id, "label"),
                    config.get_string (id, "url"), config.get_string (id, "user")));
            }
        }

        private HashTable<string, string> attributes (Book book) {
            var values = new HashTable<string, string> (str_hash, str_equal);
            values.insert ("book", book.id);
            return values;
        }

        public async void add (Book book, string token) throws Error {
            if (!(yield Secret.password_storev (token_schema, attributes (book),
                Secret.COLLECTION_DEFAULT, "Contacts · " + book.label, token, null)))
                throw new Failure.STORAGE ("The system keyring could not store the token.");
            var config = new KeyFile ();
            foreach (Book current in books) write_book (config, current);
            write_book (config, book);
            try {
                write ("books.ini", config);
            } catch (Error error) {
                try { yield Secret.password_clearv (token_schema, attributes (book), null); }
                catch (Error ignored) {}
                throw error;
            }
            books.add (book);
        }

        private void write_book (KeyFile config, Book book) {
            config.set_string (book.id, "label", book.label);
            config.set_string (book.id, "url", book.url);
            config.set_string (book.id, "user", book.user);
        }

        public async string token (Book book) throws Error {
            string? value = yield Secret.password_lookupv (token_schema, attributes (book), null);
            if (value == null || value == "")
                throw new Failure.STORAGE ("The app token is missing from the system keyring.");
            return value;
        }

        private void write (string file, KeyFile data) throws Error {
            FileUtils.set_contents_full (Path.build_filename (root, file), data.to_data (),
                -1, FileSetContentsFlags.CONSISTENT | FileSetContentsFlags.DURABLE, 0600);
        }

        public GenericArray<Contact> load (Book book) throws Error {
            var entries = new GenericArray<Contact> ();
            var data = new KeyFile ();
            string path = Path.build_filename (root, book.id + ".ini");
            if (!FileUtils.test (path, FileTest.EXISTS)) return entries;
            data.load_from_file (path, KeyFileFlags.NONE);
            foreach (string key in data.get_groups ()) {
                entries.add (new Contact (data.get_string (key, "url"),
                    data.get_string (key, "etag"), new VCard (data.get_string (key, "vcard"))));
            }
            return entries;
        }

        public void save (Book book, GenericArray<Contact> entries) throws Error {
            var data = new KeyFile ();
            foreach (Contact entry in entries) {
                string key = Checksum.compute_for_string (ChecksumType.SHA256, entry.url);
                data.set_string (key, "url", entry.url);
                data.set_string (key, "etag", entry.etag);
                data.set_string (key, "vcard", entry.card.raw);
            }
            write (book.id + ".ini", data);
        }
    }

    class DavEntry : Object {
        public string href = "";
        public string etag = "";
        public string status = "";
        public bool addressbook;
        public bool collection;
        public bool property_ok;
    }

    class DavListing : Object {
        public GenericArray<DavEntry> entries = new GenericArray<DavEntry> ();
        private GenericArray<string> path = new GenericArray<string> ();
        private DavEntry? current;
        private string prop_status = "";
        private string prop_etag = "";
        private bool prop_addressbook;
        private bool prop_collection;
        private StringBuilder value = new StringBuilder ();
        private bool multistatus;

        private static string local (string name) {
            return name.substring (name.last_index_of (":") + 1);
        }

        private string parent () {
            return path.length < 2 ? "" : path[path.length - 2];
        }

        public static bool ok (string status) {
            string[] parts = status.strip ().split (" ", 3);
            return parts.length >= 2 && parts[0].has_prefix ("HTTP/") && parts[1] == "200";
        }

        public DavListing (string xml) throws Error {
            MarkupParser parser = { start, end, characters, null, null };
            var context = new MarkupParseContext (parser, MarkupParseFlags.TREAT_CDATA_AS_TEXT, this, null);
            context.parse (xml, -1);
            context.end_parse ();
            if (!multistatus) throw new Failure.INVALID ("Expected a DAV multistatus response.");
        }

        private static void start (MarkupParseContext ctx, string name, string[] names,
            string[] values) throws MarkupError {
            unowned DavListing self = (DavListing) ctx.get_user_data ();
            string tag = local (name);
            self.path.add (tag);
            if (self.path.length == 1) self.multistatus = tag == "multistatus";
            if (tag == "response" && self.path.length == 2 && self.multistatus)
                self.current = new DavEntry ();
            if (tag == "propstat" && self.parent () == "response") {
                self.prop_status = "";
                self.prop_etag = "";
                self.prop_collection = false;
                self.prop_addressbook = false;
            }
            if (self.parent () == "resourcetype") {
                if (tag == "collection") self.prop_collection = true;
                if (tag == "addressbook") self.prop_addressbook = true;
            }
            self.value.truncate (0);
        }

        private static void characters (MarkupParseContext ctx, string value, size_t len) throws MarkupError {
            ((DavListing) ctx.get_user_data ()).value.append_len (value, (ssize_t) len);
        }

        private static void end (MarkupParseContext ctx, string name) throws MarkupError {
            unowned DavListing self = (DavListing) ctx.get_user_data ();
            string tag = local (name);
            var current = self.current;
            if (current != null) {
                string parent = self.parent ();
                string value = self.value.str.strip ();
                if (tag == "href" && parent == "response") current.href = value;
                if (tag == "status" && parent == "response") current.status = value;
                if (tag == "status" && parent == "propstat") self.prop_status = value;
                if (tag == "getetag" && parent == "prop") self.prop_etag = value;
                if (tag == "propstat" && parent == "response" && ok (self.prop_status)) {
                    current.property_ok = true;
                    if (self.prop_etag != "") current.etag = self.prop_etag;
                    current.collection |= self.prop_collection;
                    current.addressbook |= self.prop_addressbook;
                }
                if (tag == "response" && self.path.length == 2) {
                    self.entries.add (current);
                    self.current = null;
                }
            }
            self.path.remove_index (self.path.length - 1);
            self.value.truncate (0);
        }
    }

    class Dav : Object {
        private Soup.Session session = new Soup.Session ();
        private const UriFlags URI_FLAGS = UriFlags.ENCODED | UriFlags.SCHEME_NORMALIZE;
        private const string PROP_QUERY = """<?xml version="1.0" encoding="UTF-8"?>
<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/><D:getetag/></D:prop></D:propfind>""";

        public Dav () {
            session.timeout = 30;
            session.user_agent = "StandaloneContacts/0.1";
        }

        public static string book_url (string text) throws Error {
            Uri uri = Uri.parse (text.strip (), URI_FLAGS);
            string? host = uri.get_host ();
            string scheme = uri.get_scheme ();
            if (host == null || host == "" || uri.get_userinfo () != null ||
                uri.get_query () != null || uri.get_fragment () != null ||
                (scheme != "https" && !(scheme == "http" &&
                    (host == "localhost" || host == "127.0.0.1" || host == "::1"))))
                throw new Failure.INVALID ("Enter an HTTPS address book URL, with a trailing slash.");
            string url = uri.to_string ();
            return url.has_suffix ("/") ? url : url + "/";
        }

        private static bool strong (string etag) {
            return etag.length >= 2 && etag.has_prefix ("\"") && etag.has_suffix ("\"")
                && !etag.substring (1, etag.length - 2).contains ("\"")
                && !etag.contains ("\n") && !etag.contains ("\r");
        }

        private string member_url (Book book, string href, bool self_allowed = false) throws Error {
            Uri base_uri = Uri.parse (book.url, URI_FLAGS);
            Uri uri = Uri.parse_relative (base_uri, href, URI_FLAGS);
            if (href == "" || uri.get_scheme () != base_uri.get_scheme () ||
                uri.get_host () != base_uri.get_host () || uri.get_port () != base_uri.get_port () ||
                uri.get_userinfo () != null || uri.get_query () != null || uri.get_fragment () != null)
                throw new Failure.INVALID ("CardDAV returned an unexpected resource URL.");
            if (self_allowed && uri.get_path () == base_uri.get_path ()) return book.url;
            string path = uri.get_path ();
            if (!path.has_prefix (base_uri.get_path ()))
                throw new Failure.INVALID ("CardDAV returned a resource outside this address book.");
            string tail = path.substring (base_uri.get_path ().length);
            string? decoded = Uri.unescape_string (tail);
            if (decoded == null || decoded == "" || decoded == "." || decoded == ".."
                || decoded.contains ("/") || decoded.contains ("\\"))
                throw new Failure.INVALID ("CardDAV returned a resource outside this address book.");
            return uri.to_string ();
        }

        private async Bytes request (Book book, string token, string method, string url,
            string? body, string? condition, out Soup.Message response) throws Error {
            var msg = new Soup.Message (method, url);
            if (msg == null) throw new Failure.INVALID ("Invalid CardDAV URL.");
            msg.add_flags (Soup.MessageFlags.NO_REDIRECT);
            string auth = book.user + ":" + token;
            var headers = msg.get_request_headers ();
            headers.replace ("Authorization", "Basic " + Base64.encode (auth.data));
            if (method == "PROPFIND") headers.replace ("Depth", "1");
            if (condition != null) {
                if (condition != "*" && !strong (condition))
                    throw new Failure.CONFLICT ("This contact has no strong ETag. Refresh it before editing.");
                headers.replace (condition == "*" ? "If-None-Match" : "If-Match", condition);
            }
            if (body != null) msg.set_request_body_from_bytes (
                method == "PROPFIND" ? "application/xml; charset=utf-8" : "text/vcard; charset=utf-8",
                new Bytes (body.data));
            Bytes bytes = yield session.send_and_read_async (msg, Priority.DEFAULT, null);
            uint status = (uint) msg.get_status ();
            if (status == 412)
                throw new Failure.CONFLICT ("The server copy changed or already exists. Your change was refused.");
            if (status < 200 || status >= 300)
                throw new Failure.HTTP ("%s failed (HTTP %u).".printf (method, status));
            response = msg;
            return bytes;
        }

        private static string decode (Bytes bytes) throws Failure {
            if (bytes.get_size () == 0) return "";
            unowned uint8[] data = (!) bytes.get_data ();
            foreach (uint8 byte_value in data) {
                if (byte_value == 0) throw new Failure.INVALID ("Server response contains a NUL byte.");
            }
            var buffer = new StringBuilder ();
            buffer.append_len ((string) data, (ssize_t) bytes.get_size ());
            string text = buffer.str;
            if (!text.validate ()) throw new Failure.INVALID ("Server response is not UTF-8.");
            return text;
        }

        public async GenericArray<Contact> pull (Book book, string token,
            GenericArray<Contact> cached) throws Error {
            Soup.Message reply;
            Bytes body = yield request (book, token, "PROPFIND", book.url, PROP_QUERY, null, out reply);
            if (reply.get_status () != 207)
                throw new Failure.INVALID ("CardDAV did not return a 207 multistatus response.");
            var listing = new DavListing (decode (body));
            var next = new GenericArray<Contact> ();
            var seen = new HashTable<string, bool> (str_hash, str_equal);
            var previous = new HashTable<string, Contact> (str_hash, str_equal);
            foreach (Contact entry in cached) previous.insert (entry.url, entry);
            bool confirmed = false;
            foreach (DavEntry item in listing.entries) {
                if ((item.status != "" && !DavListing.ok (item.status)) || !item.property_ok)
                    throw new Failure.INVALID ("CardDAV returned an incomplete address book listing.");
                string url = member_url (book, item.href, true);
                if (url == book.url) {
                    if (confirmed || !item.addressbook || !item.collection)
                        throw new Failure.INVALID ("This URL is not a CardDAV address book.");
                    confirmed = true;
                    continue;
                }
                if (item.collection || seen.contains (url))
                    throw new Failure.INVALID ("CardDAV returned an unexpected or duplicate resource.");
                seen.insert (url, true);
                var old = previous.lookup (url);
                if (old != null && strong (item.etag) && item.etag == old.etag) {
                    next.add (old);
                    continue;
                }
                Bytes card_body = yield request (book, token, "GET", url,
                    null, strong (item.etag) ? item.etag : null, out reply);
                if (reply.get_status () != 200)
                    throw new Failure.INVALID ("CardDAV did not return a complete contact.");
                string etag = reply.get_response_headers ().get_one ("ETag") ?? "";
                if (strong (item.etag) && item.etag != etag)
                    throw new Failure.CONFLICT ("The address book changed during refresh. Try refreshing again.");
                var cards = VCard.parse_file (decode (card_body));
                if (cards.length != 1)
                    throw new Failure.INVALID ("A CardDAV resource must contain exactly one vCard.");
                next.add (new Contact (url, etag, cards[0]));
            }
            if (!confirmed)
                throw new Failure.INVALID ("The server did not identify the address book.");
            return next;
        }

        public async void put (Book book, string token, string url, string? etag, VCard card) throws Error {
            Soup.Message reply;
            if (etag != null && !strong (etag))
                throw new Failure.CONFLICT ("This contact has no strong ETag. Refresh it before editing.");
            yield request (book, token, "PUT", member_url (book, url), card.raw, etag ?? "*", out reply);
        }

        public async void remove (Book book, string token, Contact contact) throws Error {
            if (!strong (contact.etag))
                throw new Failure.CONFLICT ("This contact has no strong ETag. Refresh it before deleting.");
            Soup.Message reply;
            yield request (book, token, "DELETE", member_url (book, contact.url),
                null, contact.etag, out reply);
        }
    }
}
