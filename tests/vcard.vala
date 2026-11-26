using Contacts;

const string ORIGINAL = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:original\r\n"
    + "FN:Old Name\r\nitem1.EMAIL;TYPE=HOME:hi@example.test\r\n"
    + "X-KEEP:original bytes\r\n continued\r\nPHOTO;ENCODING=b:AQID\r\nEND:VCARD\r\n";

void test_round_trip () {
    try {
        var cards = VCard.parse_file (ORIGINAL + ORIGINAL.replace ("\r\n", "\n"));
        assert (cards.length == 2);
        assert (cards[0].raw == ORIGINAL);
        assert (cards[1].raw == ORIGINAL.replace ("\r\n", "\n"));
        assert (cards[0].read ("EMAIL") == "hi@example.test");
        assert (cards[0].read ("X-KEEP") == "original bytescontinued");
        assert (cards[0].photo ().get_size () == 3);
        assert (cards[0].edit ("Old Name", "hi@example.test", "", "", "").raw == ORIGINAL);
        assert (cards[0].edit ("New, Name", "hi@example.test", "", "", "").raw ==
            ORIGINAL.replace ("FN:Old Name", "FN:New\\, Name"));
    } catch (Error error) { assert_not_reached (); }
}

void test_fold () {
    try {
        string name = ("0123456789012345678901234567890123456789" + "012345678901234567890123456789") + "éééé";
        var card = new VCard (ORIGINAL).edit (name, "hi@example.test", "", "", "");
        assert (card.name == name);
        assert (card.raw.contains ("\r\n é"));
        foreach (string line in card.raw.split ("\r\n")) assert (line.length <= 75);
    } catch (Error error) { assert_not_reached (); }
}

void test_edit_fields () {
    try {
        string fields = "EMAIL;TYPE=WORK:work@example.test\r\n"
            + "TEL;VALUE=uri:tel:+441234567890\r\n"
            + "ORG:Example\\; Ltd;Engineering;Support\r\n";
        var card = new VCard (ORIGINAL.replace ("END:VCARD", fields + "END:VCARD"));
        assert (card.read ("ORG") == "Example; Ltd");

        var edited = card.edit ("Old Name", "other@example.test", "+449876543210",
            "New; Ltd", "First line\nSecond line");
        assert (edited.raw == card.raw
            .replace ("HOME:hi@example.test", "HOME:other@example.test")
            .replace ("tel:+441234567890", "tel:+449876543210")
            .replace ("ORG:Example\\; Ltd", "ORG:New\\; Ltd")
            .replace ("END:VCARD", "NOTE:First line\\nSecond line\r\nEND:VCARD"));
        assert (edited.read ("ORG") == "New; Ltd");
        assert (edited.read ("NOTE") == "First line\nSecond line");

        var cleared = edited.edit ("Old Name", "", "", "", "");
        assert (cleared.read ("EMAIL") == "work@example.test");
        assert (cleared.raw.contains ("ORG:;Engineering;Support\r\n"));
        assert (!cleared.raw.contains ("TEL;"));
        assert (!cleared.raw.contains ("NOTE:"));
    } catch (Error error) { assert_not_reached (); }
}

void test_incomplete () {
    try {
        VCard.parse_file (ORIGINAL + "BEGIN:VCARD\nFN:Truncated");
        assert_not_reached ();
    } catch (Failure.INVALID expected) {
    } catch (Error error) { assert_not_reached (); }
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/vcard/round-trip", test_round_trip);
    Test.add_func ("/vcard/utf8-fold", test_fold);
    Test.add_func ("/vcard/edit-fields", test_edit_fields);
    Test.add_func ("/vcard/reject-incomplete-file", test_incomplete);
    return Test.run ();
}
