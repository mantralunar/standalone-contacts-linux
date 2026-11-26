namespace Contacts {
    errordomain Failure { INVALID, HTTP, CONFLICT, STORAGE }

    class VCard : Object {
        public string raw { get; private set; }
        private string? cached_name;
        private string? cached_folded_name;
        public string name {
            owned get {
                if (cached_name == null) cached_name = read ("FN");
                return cached_name;
            }
        }
        public string folded_name {
            owned get {
                if (cached_folded_name == null) cached_folded_name = name.casefold ();
                return cached_folded_name;
            }
        }

        public VCard (string raw) throws Failure {
            int start = 0;
            int end = raw.length;
            while (start < end && raw[start].isspace ()) start++;
            while (end > start && raw[end - 1].isspace ()) end--;
            if (end - start < 20 || !raw.validate () ||
                raw.substring (start, 11).ascii_up () != "BEGIN:VCARD" ||
                raw.substring (end - 9, 9).ascii_up () != "END:VCARD")
                throw new Failure.INVALID ("Expected a UTF-8 vCard.");
            this.raw = raw;
        }

        private static int separator (string line) {
            bool quoted = false;
            for (int i = 0; i < line.length; i++) {
                if (line[i] == '"') quoted = !quoted;
                if (line[i] == ':' && !quoted) return i;
            }
            return -1;
        }

        private static string property_name (string line, int colon) {
            if (colon < 0) return "";
            string key = line.substring (0, colon).split (";", 2)[0];
            return key.substring (key.last_index_of (".") + 1).up ();
        }

        private string logical_line (string[] lines, ref int index) {
            var line = new StringBuilder (lines[index].has_suffix ("\r")
                ? lines[index].substring (0, lines[index].length - 1) : lines[index]);
            while (index + 1 < lines.length &&
                (lines[index + 1].has_prefix (" ") || lines[index + 1].has_prefix ("\t"))) {
                index++;
                string part = lines[index];
                int end = part.has_suffix ("\r") ? part.length - 1 : part.length;
                line.append_len (part.substring (1), end - 1);
            }
            return line.str;
        }

        // Scan physical lines without copying unrelated properties such as folded PHOTO data.
        private string? find_property (string key) {
            int limit = raw.length;
            int start = 0;
            while (start < limit) {
                int end = raw.index_of_char ('\n', start);
                if (end < 0) end = limit;
                bool continuation = raw[start] == ' ' || raw[start] == '\t';
                if (continuation) {
                    start = end + 1;
                    continue;
                }
                bool folded = end + 1 < limit && (raw[end + 1] == ' ' || raw[end + 1] == '\t');
                bool quoted = false;
                int colon = start;
                for (; colon < end; colon++) {
                    if (raw[colon] == '"') quoted = !quoted;
                    if (raw[colon] == ':' && !quoted) break;
                }
                if (colon < end && property_name (raw.substring (start, colon - start),
                    colon - start) != key) {
                    start = end + 1;
                    continue;
                }
                if (colon == end && !folded) {
                    start = end + 1;
                    continue;
                }

                var line = new StringBuilder ();
                int part_start = start;
                while (true) {
                    int trim_end = end > part_start && raw[end - 1] == '\r' ? end - 1 : end;
                    line.append_len (raw.offset (part_start), trim_end - part_start);
                    start = end + 1;
                    if (start >= limit || (raw[start] != ' ' && raw[start] != '\t')) break;
                    part_start = start + 1;
                    end = raw.index_of_char ('\n', part_start);
                    if (end < 0) end = limit;
                }
                int value_start = separator (line.str);
                if (property_name (line.str, value_start) == key) return line.str;
            }
            return null;
        }

        public string read (string key) {
            string? line = find_property (key);
            if (line == null) return "";
            string value = line.substring (separator (line) + 1);
            int units = key == "ORG" ? organisation_separator (value) : -1;
            return unescape (units >= 0 ? value.substring (0, units) : value);
        }

        private static string unescape (string value) {
            var result = new StringBuilder ();
            for (int i = 0; i < value.length; i++) {
                if (value[i] == '\\' && i + 1 < value.length) {
                    char next = value[i + 1];
                    if (next == 'n' || next == 'N') { result.append_c ('\n'); i++; continue; }
                    if (next == '\\' || next == ',' || next == ';') i++;
                }
                result.append_c (value[i]);
            }
            return result.str;
        }

        private static string escape (string value) {
            return value.replace ("\\", "\\\\").replace ("\r\n", "\n").replace ("\r", "\n")
                .replace ("\n", "\\n").replace (",", "\\,").replace (";", "\\;");
        }

        private static string fold (string line, string newline) {
            var result = new StringBuilder ();
            int index = 0, column = 0;
            unichar ch;
            while (line.get_next_char (ref index, out ch)) {
                int width = ch.to_utf8 (null);
                if (column + width > 75) {
                    result.append (newline + " ");
                    column = 1;
                }
                result.append_unichar (ch);
                column += width;
            }
            return result.str;
        }

        private static int organisation_separator (string value) {
            for (int i = 0; i < value.length; i++) {
                if (value[i] == '\\') i++;
                else if (value[i] == ';') return i;
            }
            return -1;
        }

        public VCard edit (string name, string email, string phone, string organisation,
            string notes) throws Failure {
            if (name.strip () == "")
                throw new Failure.INVALID ("Enter a contact name.");
            return update_field ("FN", name).update_field ("EMAIL", email)
                .update_field ("TEL", phone).update_field ("ORG", organisation)
                .update_field ("NOTE", notes);
        }

        private VCard update_field (string field, string text) throws Failure {
            if (text == read (field)) return this;
            string[] lines = raw.split ("\n");
            for (int i = 0; i < lines.length; i++) {
                int first = i;
                string line = logical_line (lines, ref i);
                int colon = separator (line);
                string key = property_name (line, colon);
                bool insert = key == "END" && line.substring (colon + 1).up () == "VCARD";
                if (key != field && !insert) continue;

                string prefix = insert ? field + ":" : line.substring (0, colon + 1);
                string params = prefix.up ();
                if (params.contains ("ENCODING=") || params.contains ("CHARSET="))
                    throw new Failure.INVALID ("The %s field uses a legacy vCard encoding.".printf (field));
                string previous = insert ? "" : line.substring (colon + 1);
                string value = escape (text);
                if (field == "TEL" && text != "" &&
                    (previous.ascii_down ().has_prefix ("tel:") || params.contains ("VALUE=URI"))) {
                    string uri = text;
                    if (!uri.contains (":") && previous.ascii_down ().has_prefix ("tel:"))
                        uri = "tel:" + uri;
                    try { Uri.parse (uri, UriFlags.NONE); }
                    catch (UriError error) {
                        throw new Failure.INVALID ("Use a valid phone URI for this contact, such as tel:+441234567890.");
                    }
                    value = uri;
                }
                int units = field == "ORG" ? organisation_separator (previous) : -1;
                if (units >= 0) value += previous.substring (units);

                string newline = lines[first].has_suffix ("\r") ? "\r\n" : "\n";
                var result = new StringBuilder ();
                for (int j = 0; j < first; j++) result.append (lines[j] + "\n");
                if (value != "") result.append (fold (prefix + value, newline) + newline);
                for (int j = insert ? first : i + 1; j < lines.length; j++) {
                    result.append (lines[j]);
                    if (j + 1 < lines.length) result.append_c ('\n');
                }
                return new VCard (result.str);
            }
            throw new Failure.INVALID ("Missing vCard end marker.");
        }

        public Bytes? photo () {
            string[] lines = raw.split ("\n");
            for (int i = 0; i < lines.length; i++) {
                string line = logical_line (lines, ref i);
                int colon = separator (line);
                if (property_name (line, colon) != "PHOTO") continue;
                string head = line.substring (0, colon).down ();
                string value = line.substring (colon + 1);
                if (value.down ().has_prefix ("data:image/")) {
                    int comma = value.index_of (",");
                    if (comma < 0 || !value.substring (0, comma).down ().has_suffix (";base64")) continue;
                    value = value.substring (comma + 1);
                } else if (!head.contains (";encoding=b;") && !head.has_suffix (";encoding=b")
                    && !head.contains (";encoding=base64;") && !head.has_suffix (";encoding=base64")) {
                    continue;
                }
                if (value.length <= 8 * 1024 * 1024) return new Bytes.take (Base64.decode (value));
            }
            return null;
        }

        public static VCard create (string name, string uid) throws Failure {
            return new VCard ("BEGIN:VCARD\r\nVERSION:3.0\r\nUID:" + uid + "\r\n"
                + fold ("FN:" + escape (name), "\r\n") + "\r\n"
                + fold ("N:" + escape (name) + ";;;;", "\r\n") + "\r\nEND:VCARD\r\n");
        }

        public static GenericArray<VCard> parse_file (string input) throws Failure {
            var cards = new GenericArray<VCard> ();
            int start = -1, offset = 0;
            foreach (string physical in input.split ("\n")) {
                string marker = (physical.has_suffix ("\r")
                    ? physical.substring (0, physical.length - 1) : physical).up ();
                int end = offset + physical.length;
                if (end < input.length) end++;
                if (marker == "BEGIN:VCARD" && start < 0) start = offset;
                else if (marker == "END:VCARD" && start >= 0) {
                    cards.add (new VCard (input.substring (start, end - start)));
                    start = -1;
                } else if (marker == "BEGIN:VCARD" || (start < 0 && physical.strip () != ""))
                    throw new Failure.INVALID ("Unexpected content in the vCard file.");
                offset = end;
            }
            if (start >= 0 || cards.length == 0)
                throw new Failure.INVALID ("Missing or incomplete vCard.");
            return cards;
        }
    }

    class VCardReader : Object {
        private InputStream input;
        private Bytes chunk = new Bytes (null);
        private size_t offset;
        private bool eof;
        private bool saw_card;
        public uint64 bytes_read { get; private set; }

        public VCardReader (InputStream input) {
            this.input = input;
        }

        private async string? next_line () throws Error {
            var line = new StringBuilder ();
            while (!eof) {
                if (offset == chunk.get_size ()) {
                    chunk = yield input.read_bytes_async (64 * 1024, Priority.DEFAULT, null);
                    offset = 0;
                    bytes_read += chunk.get_size ();
                    if (chunk.get_size () == 0) {
                        eof = true;
                        break;
                    }
                }
                unowned uint8[] data = (!) chunk.get_data ();
                size_t start = offset;
                while (offset < chunk.get_size ()) {
                    uint8 value = data[offset++];
                    if (value == 0) throw new Failure.INVALID ("The vCard file contains a NUL byte.");
                    if (value == '\n') break;
                }
                line.append_len ((string) ((uint8*) data + start), (ssize_t) (offset - start));
                if (data[offset - 1] == '\n') break;
            }
            return line.len == 0 ? null : line.str;
        }

        public async VCard? next () throws Error {
            var card = new StringBuilder ();
            string? line;
            while ((line = yield next_line ()) != null) {
                // Compare only the marker-sized lines. A photo may occupy a very long line.
                string marker = "";
                if (line.length <= 13) {
                    int length = line.length;
                    if (length > 0 && line[length - 1] == '\n') length--;
                    if (length > 0 && line[length - 1] == '\r') length--;
                    marker = line.substring (0, length).ascii_up ();
                }
                if (marker == "BEGIN:VCARD" && card.len == 0) {
                    card.append (line);
                } else if (marker == "BEGIN:VCARD" || (card.len == 0 && line.strip () != "")) {
                    throw new Failure.INVALID ("Unexpected content in the vCard file.");
                } else if (card.len != 0) {
                    card.append (line);
                    if (marker == "END:VCARD") {
                        saw_card = true;
                        return new VCard (card.str);
                    }
                }
            }
            if (card.len != 0 || !saw_card)
                throw new Failure.INVALID ("Missing or incomplete vCard.");
            return null;
        }
    }

}
