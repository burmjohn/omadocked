import QtQuick
import QtTest
import "../../services/FolderLogic.js" as Folder

TestCase {
    name: "FolderLogic"

    function request(path, generation, token) {
        return Folder.request(path, generation, token);
    }

    function payload(req, entries, extra) {
        const value = Object.assign({version: 1, generation: req.generation, token: req.token,
            status: entries.length ? "ok" : "empty", complete: true,
            inspected: entries.length, total: entries.length, omitted: 0,
            rootIdentity: {device: "2049", inode: "123456"},
            entries: entries, receipt: {generation: req.generation, token: req.token,
                inspected: entries.length, complete: true}}, extra || {});
        return value;
    }

    function row(req, name, type, category) {
        return {name: name, path: req.path + "/" + name, type: type || "file",
            size: type === "file" || !type ? 12 : null, mtimeNs: "1800000000000000000",
            relativeTime: "10 seconds ago", iconCategory: category || "document"};
    }

    function test_requestIdentityRejectsStaleResults() {
        const one = request("/tmp/exact folder", 11, "stable_token-11");
        compare(one.path, "/tmp/exact folder");
        compare(one.generation, 11);
        compare(one.token, "stable_token-11");
        verify(Folder.accepts(one, payload(one, [])));
        verify(!Folder.accepts(one, Object.assign({}, payload(one, []), {generation: 10})));
        verify(!Folder.accepts(one, Object.assign({}, payload(one, []), {token: "other"})));
        for (const args of [["relative", 1, "token"], ["/tmp", -1, "token"],
                            ["/tmp", 1.5, "token"], ["/tmp", 1, "bad token"], ["/tmp", 1, ""]]) {
            let failed = false;
            try { Folder.request(args[0], args[1], args[2]); } catch (e) { failed = true; }
            verify(failed, JSON.stringify(args));
        }
    }

    function test_normalizesExactBoundedResultAndAccurateRemainder() {
        const req = request("/tmp/a b", 2, "token_2");
        const entries = [];
        for (let i = 0; i < 16; ++i) entries.push(row(req, "item " + (i < 10 ? "0" : "") + i, "file", "document"));
        const result = Folder.normalize(payload(req, entries, {inspected: 19, total: 19, omitted: 3,
            receipt: {generation: 2, token: "token_2", inspected: 19, complete: true}}), req);
        compare(result.entries.length, 16);
        compare(result.remainingLabel, "+3");
        compare(result.entries[0].path, "/tmp/a b/item 00");
        compare(result.entries[0].size, 12);
        compare(result.entries[0].icon, "text-x-generic-symbolic");
    }

    function test_tooLargeNeverInventsAnExactRemainder() {
        const req = request("/tmp/large", 3, "large");
        const result = Folder.normalize({version: 1, generation: 3, token: "large",
            status: "too-large", complete: false, inspected: 512, observedAtLeast: 513,
            entries: [], error: {code: "too-large", message: Folder.message("too-large")},
            receipt: {generation: 3, token: "large", inspected: 512, complete: false}}, req);
        compare(result.remainingLabel, "More items");
        compare(result.entries.length, 0);
        verify(!("omitted" in result));
    }

    function test_safeVisibleLabelsAndAllowlistedIcons() {
        const req = request("/tmp/control", 4, "control");
        const result = Folder.normalize(payload(req, [row(req, "line\nbreak\tname", "symlink", "link")]), req);
        compare(result.entries[0].name, "line\nbreak\tname");
        compare(result.entries[0].label, "line�break�name");
        compare(result.entries[0].icon, "emblem-symbolic-link-symbolic");
        compare(Folder.icon("folder", "directory"), "folder-symbolic");
        compare(Folder.icon("image", "file"), "image-x-generic-symbolic");
        compare(Folder.icon("hostile-icon-name", "other"), "unknown-symbolic");
    }

    function test_posixBackslashFilenameMatchesScannerContract() {
        const req = request("/tmp/backslash", 7, "backslash");
        const result = Folder.normalize(payload(req, [row(req, "literal\\name", "file", "document")]), req);
        compare(result.entries[0].name, "literal\\name");
        compare(result.entries[0].path, "/tmp/backslash/literal\\name");
    }

    function test_completedResultPreservesValidatedRootIdentity() {
        const req = request("/tmp/anchor", 8, "anchor");
        const result = Folder.normalize(payload(req, []), req);
        compare(result.rootIdentity, {device: "2049", inode: "123456"});
        let failed = false;
        try { Folder.normalize(payload(req, [], {rootIdentity:{device:2049, inode:"123456"}}), req); }
        catch (_) { failed = true; }
        verify(failed);
    }

    function test_rejectsMalformedUntrustedHelperOutput() {
        const req = request("/tmp/exact", 5, "exact");
        const good = payload(req, [row(req, "safe", "file", "document")]);
        const bad = [
            Object.assign({}, good, {status: "hostile"}),
            Object.assign({}, good, {total: 2}),
            Object.assign({}, good, {omitted: 1}),
            Object.assign({}, good, {entries: [Object.assign({}, good.entries[0], {path: "/tmp/other"})]}),
            Object.assign({}, good, {entries: [Object.assign({}, good.entries[0], {name: ".hidden"})]}),
            Object.assign({}, good, {entries: [Object.assign({}, good.entries[0], {relativeTime: "secret\nleak"})]}),
            Object.assign({}, good, {receipt: {path: "/private", generation: 5, token: "exact", inspected: 1, complete: true}})
        ];
        for (const value of bad) {
            let failed = false;
            try { Folder.normalize(value, req); } catch (e) { failed = true; }
            verify(failed, JSON.stringify(value));
        }
    }

    function test_distinctEmptyAndErrorStatesRemainPrivate() {
        const req = request("/tmp/private-path", 6, "states");
        for (const state of ["empty", "missing", "not-directory", "unreadable", "timeout", "cancelled", "changed"]) {
            const complete = state === "empty";
            const value = {version: 1, generation: 6, token: "states", status: state,
                complete: complete, inspected: 0, entries: [], error: state === "empty" ? undefined : {code: state, message: Folder.message(state)},
                receipt: {generation: 6, token: "states", inspected: 0, complete: complete}};
            if (complete) { value.total = 0; value.omitted = 0; value.rootIdentity = {device:"1", inode:"2"}; }
            const result = Folder.normalize(value, req);
            compare(result.status, state);
            verify(result.message.indexOf("/tmp/private-path") === -1);
        }
    }
}
