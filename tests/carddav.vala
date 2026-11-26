using Contacts;

const string TOKEN = "app-token";
const string ETAG = "\"v1\"";
const string CARD = "BEGIN:VCARD\r\nVERSION:3.0\r\nUID:one\r\nFN:Original\r\nEND:VCARD\r\n";
const string LIST = """<?xml version="1.0"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:carddav">
  <D:response><D:href>/book/</D:href><D:propstat>
    <D:prop><D:resourcetype><D:collection/><C:addressbook/></D:resourcetype></D:prop>
    <D:status>HTTP/1.1 200 OK</D:status>
  </D:propstat></D:response>
  <D:response><D:href>/book/one.vcf</D:href><D:propstat>
    <D:prop><D:resourcetype/><D:getetag>&quot;v1&quot;</D:getetag></D:prop>
    <D:status>HTTP/1.1 200 OK</D:status>
  </D:propstat></D:response>
</D:multistatus>""";

class Fixture : Object {
    private Soup.Server server = new Soup.Server ("server-header", "Standalone Contacts test", null);
    private uint gets;
    private bool reject_get;
    private bool updated;

    public async void check () throws Error {
        server.add_handler (null, serve);
        server.listen_local (0, Soup.ServerListenOptions.IPV4_ONLY);
        var uris = server.get_uris ();
        var url = Dav.book_url (uris.data.to_string () + "book/");
        var book = new Book (Uuid.string_random (), "Test", url, "test");
        var client = new Dav ();
        var account = new Book ("", "", uris.data.to_string (), "test");
        var found = yield client.discover (account, TOKEN);
        assert (found.length == 1 && found[0].url == url && found[0].label == "Personal");
        if (found.length == 1) {
            var direct = yield client.discover (found[0], TOKEN);
            assert (direct.length == 1 && direct[0].url == url);
        }
        var cache = yield client.pull (book, TOKEN, new GenericArray<Contact> ());
        assert (cache.length == 1 && cache[0].card.raw == CARD && cache[0].etag == ETAG);
        assert (gets == 1);
        var unchanged = yield client.pull (book, TOKEN, cache);
        assert (unchanged.length == 1 && gets == 1);
        try {
            yield client.put (book, TOKEN, cache[0].url, "\"stale\"", cache[0].card);
            assert_not_reached ();
        } catch (Failure.CONFLICT expected) {}
        assert (!updated);
        yield client.put (book, TOKEN, cache[0].url, ETAG, cache[0].card);
        assert (updated);
        try {
            yield client.put (book, TOKEN, cache[0].url, "*", cache[0].card);
            assert_not_reached ();
        } catch (Failure.CONFLICT expected) {}
        try {
            yield client.put (book, TOKEN, cache[0].url, null, cache[0].card);
            assert_not_reached ();
        } catch (Failure.CONFLICT expected) {}
        reject_get = true;
        try {
            yield client.pull (book, TOKEN, new GenericArray<Contact> ());
            assert_not_reached ();
        } catch (Failure.HTTP expected) {}
        assert (cache[0].card.raw == CARD);
        yield client.remove (book, TOKEN, cache[0]);
        server.disconnect ();
    }

    private void serve (Soup.Server server, Soup.ServerMessage msg, string path,
        HashTable<string, string>? query) {
        var headers = msg.get_request_headers ();
        assert (headers.get_one ("Authorization") == "Basic dGVzdDphcHAtdG9rZW4=");
        switch (msg.get_method ()) {
            case "PROPFIND":
                if (serve_discovery (msg, path, headers.get_one ("Depth") ?? "")) break;
                assert (path == "/book/" && headers.get_one ("Depth") == "1");
                reply (msg, 207, "application/xml", LIST);
                break;
            case "GET":
                assert (path == "/book/one.vcf" && headers.get_one ("If-Match") == ETAG);
                gets++;
                if (reject_get) {
                    msg.set_status (500, null);
                    break;
                }
                msg.get_response_headers ().replace ("ETag", ETAG);
                reply (msg, 200, "text/vcard", CARD);
                break;
            case "PUT":
                assert (path == "/book/one.vcf");
                if (headers.get_one ("If-Match") == ETAG) {
                    updated = true;
                    msg.set_status (204, null);
                } else {
                    assert (headers.get_one ("If-Match") == "\"stale\""
                        || headers.get_one ("If-None-Match") == "*");
                    msg.set_status (412, null);
                }
                break;
            case "DELETE":
                assert (path == "/book/one.vcf" && headers.get_one ("If-Match") == ETAG);
                msg.set_status (204, null);
                break;
            default:
                assert_not_reached ();
        }
    }

    private bool serve_discovery (Soup.ServerMessage msg, string path, string depth) {
        string prop;
        switch (path) {
            case "/.well-known/carddav":
                assert (depth == "0");
                msg.set_redirect (301, "/carddav/");
                return true;
            case "/carddav/":
                assert (depth == "0");
                prop = "<D:current-user-principal><D:href>/account/</D:href></D:current-user-principal>";
                break;
            case "/account/":
                assert (depth == "0");
                prop = "<C:addressbook-home-set><D:href>/home/</D:href></C:addressbook-home-set>";
                break;
            case "/home/":
                assert (depth == "1");
                path = "/book/";
                prop = "<D:resourcetype><D:collection/><C:addressbook/></D:resourcetype>"
                    + "<D:displayname>Personal</D:displayname>";
                break;
            case "/book/":
                if (depth != "0") return false;
                prop = "<D:resourcetype><D:collection/><C:addressbook/></D:resourcetype>";
                break;
            default:
                return false;
        }
        string xml = "<D:multistatus xmlns:D=\"DAV:\" xmlns:C=\"urn:ietf:params:xml:ns:carddav\">"
            + "<D:response><D:href>" + path + "</D:href><D:propstat><D:prop>" + prop
            + "</D:prop><D:status>HTTP/1.1 200 OK</D:status></D:propstat></D:response></D:multistatus>";
        reply (msg, 207, "application/xml", xml);
        return true;
    }

    private void reply (Soup.ServerMessage msg, uint status, string type, string body) {
        msg.set_status (status, null);
        msg.set_response (type, Soup.MemoryUse.COPY, body.data);
    }
}

int main () {
    var loop = new MainLoop ();
    var fixture = new Fixture ();
    int result = 1;
    fixture.check.begin ((obj, task) => {
        try {
            fixture.check.end (task);
            result = 0;
        } catch (Error error) { stderr.printf ("%s\n", error.message); }
        loop.quit ();
    });
    loop.run ();
    return result;
}
