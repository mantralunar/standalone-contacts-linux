namespace Contacts {
    errordomain Failure { INVALID, HTTP, CONFLICT, STORAGE }

    class VCard : Object {
        public string raw { get; private set; }
        public string name { owned get { return read ("FN"); } }

        public VCard (string raw) throws Failure {
            if (!raw.validate () || !raw.strip ().up ().has_prefix ("BEGIN:VCARD")
                || !raw.strip ().up ().has_suffix ("END:VCARD"))
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

        public string read (string key) {
            string[] lines = raw.split ("\n");
            for (int i = 0; i < lines.length; i++) {
                var line = logical_line (lines, ref i);
                int colon = separator (line);
                if (property_name (line, colon) == key) {
                    string value = line.substring (colon + 1);
                    int units = key == "ORG" ? organisation_separator (value) : -1;
                    return unescape (units >= 0 ? value.substring (0, units) : value);
                }
            }
            return "";
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
}
