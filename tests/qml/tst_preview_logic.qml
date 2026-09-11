import QtQuick
import QtTest
import "../../core/PreviewLogic.js" as Preview

TestCase {
    name: "PreviewLogic"

    function row(key, appId, title, parkedAt) {
        return {key: key, appId: appId, title: title, parkedAt: parkedAt};
    }

    function capture(signature, options) {
        return Preview.newCapture(signature, Object.assign({captureToken: "test-token", generation: 1}, options || {}));
    }

    function captureEvent(state, type, extra) {
        return Object.assign({type: type, captureToken: state.captureToken,
            identitySignature: state.identitySignature, generation: state.generation}, extra || {});
    }

    function test_activeModeBuildsSingleCardsInOldestOrder() {
        const cards = Preview.buildCards("active", [
            row("new", "same", "New", 30),
            row("old", "same", "Old", 10),
            row("middle", "same", "Middle", 20)
        ]);
        compare(cards.length, 3);
        compare(cards.map(card => card.representativeKey), ["old", "middle", "new"]);
        compare(cards.map(card => card.count), [1, 1, 1]);
        compare(cards.map(card => card.memberKeys), [["old"], ["middle"], ["new"]]);
    }

    function test_allModeGroupsExactAppsByOldestMember() {
        const cards = Preview.buildCards("all", [
            row("a-new", "alpha", "A new", 40),
            row("b-old", "beta", "B old", 10),
            row("a-old", "alpha", "A old", 20),
            row("no-app", "", "Independent", 5)
        ]);
        compare(cards.length, 3);
        compare(cards.map(card => card.representativeKey), ["no-app", "b-old", "a-old"]);
        compare(cards.map(card => card.count), [1, 1, 2]);
        compare(cards[2].memberKeys, ["a-old", "a-new"]);
    }

    function test_groupTitlesAreSanitizedLimitedAndExactlyCounted() {
        const rows = [];
        for (let i = 0; i < 8; ++i)
            rows.push(row("w" + i, "alpha", i === 0 ? "  First\n title  " : (i === 1 ? "\u0000" : "Title " + i), i));
        const card = Preview.buildCards("all", rows)[0];
        compare(card.count, 8);
        compare(card.titles, ["First title", "Untitled window", "Title 2", "Title 3", "Title 4", "Title 5"]);
        compare(card.remainingTitleCount, 2);
        compare(card.titleSummary, "First title\nUntitled window\nTitle 2\nTitle 3\nTitle 4\nTitle 5\n+2");
    }

    function test_buildCardsRejectsMalformedDuplicateAndOversizedRecords() {
        compare(Preview.buildCards("active", [null]), []);
        compare(Preview.buildCards("active", [row(1, "app", "numeric", 1)]), []);
        compare(Preview.buildCards("active", [row("dup", "app", "one", 1), row("dup", "app", "two", 2)]), []);
        compare(Preview.buildCards("all", [row("ok", {}, "object app", 1)]), []);
        const oversized = [];
        for (let i = 0; i < 513; ++i) oversized.push(row("key-" + i, "app", "title", i));
        compare(Preview.buildCards("all", oversized), []);
        compare(Preview.buildCards("active", [row("x".repeat(513), "app", "title", 1)]), []);
    }

    function test_identitySignatureChangesOnlyWithModeOrMembership() {
        const before = Preview.buildCards("all", [row("one|two", "alpha", "Old", 1), row("three", "alpha", "Three", 2)])[0];
        const metadata = Preview.buildCards("all", [row("three", "alpha", "Renamed", 2), row("one|two", "alpha", "New title", 1)])[0];
        compare(metadata.identitySignature, before.identitySignature);
        verify(metadata.titleSummary !== before.titleSummary);
        const removed = Preview.buildCards("all", [row("one|two", "alpha", "New title", 1)])[0];
        verify(removed.identitySignature !== before.identitySignature);
        const active = Preview.buildCards("active", [row("one|two", "alpha", "New title", 1)])[0];
        verify(active.identitySignature !== removed.identitySignature);
    }

    function test_staleCaptureEventsCannotCrossIdentityGenerationOrToken() {
        const state = Preview.newCapture("identity", {captureToken: "capture-a", generation: 7});
        const staleEvents = [
            {type: "capture-ready", captureToken: "capture-old", identitySignature: "identity", generation: 7},
            {type: "capture-ready", captureToken: "capture-a", identitySignature: "other", generation: 7},
            {type: "capture-ready", captureToken: "capture-a", identitySignature: "identity", generation: 6},
            {type: "capture-failed", captureToken: "capture-old", identitySignature: "identity", generation: 7}
        ];
        staleEvents.forEach(function(event) {
            compare(JSON.stringify(Preview.reduceCapture(state, event)), JSON.stringify(state), JSON.stringify(event));
        });
        const accepted = Preview.reduceCapture(state, {
            type: "capture-ready", captureToken: "capture-a", identitySignature: "identity", generation: 7
        });
        verify(accepted.hasStill);
    }

    function test_captureStartsInExplicitPreParkReadiness() {
        const state = capture("identity", {maxAttempts: 3, allowLive: true});
        compare(state.identitySignature, "identity");
        compare(state.readiness, "pre-park");
        compare(state.attempts, 0);
        compare(state.maxAttempts, 3);
        verify(state.captureRequested);
        verify(!state.canPark);
        verify(!state.live);
    }

    function test_captureFailureHasFiniteLifetimeAndTerminalFallback() {
        let state = capture("identity", {maxAttempts: 3});
        state = Preview.reduceCapture(state, captureEvent(state, "capture-failed"));
        state = Preview.reduceCapture(state, captureEvent(state, "capture-failed"));
        verify(!state.terminal);
        state = Preview.reduceCapture(state, captureEvent(state, "capture-failed"));
        compare(state.attempts, 3);
        compare(state.readiness, "fallback");
        verify(state.terminal);
        verify(state.fallback);
        verify(state.canPark);
        verify(!state.captureRequested);
        const stoppedAgain = Preview.reduceCapture(state, captureEvent(state, "capture-stopped"));
        compare(JSON.stringify(stoppedAgain), JSON.stringify(state));
        compare(capture("bounded-high", {maxAttempts: 99}).maxAttempts, 6);
        compare(capture("bounded-low", {maxAttempts: 0}).maxAttempts, 1);
    }

    function test_readyStillCanGoLiveOnlyWhilePopupVisible() {
        let state = capture("identity", {allowLive: true});
        state = Preview.reduceCapture(state, captureEvent(state, "capture-ready"));
        compare(state.readiness, "ready");
        compare(state.attempts, 1, "successful frame is part of the finite total attempt budget");
        verify(state.hasStill);
        verify(state.canPark);
        verify(!state.captureRequested);
        verify(!state.live);
        state = Preview.reduceCapture(state, {type: "popup-visible", visible: true});
        verify(state.live);
        state = Preview.reduceCapture(state, {type: "popup-visible", visible: false});
        verify(!state.live);
        let disabled = capture("still", {allowLive: false});
        disabled = Preview.reduceCapture(disabled, captureEvent(disabled, "capture-ready"));
        disabled = Preview.reduceCapture(disabled, {type: "popup-visible", visible: true});
        verify(!disabled.live);
    }

    function test_unsafeLifecycleSignalsImmediatelyTearDownCapture() {
        const events = [
            {type: "owner-visible", visible: false},
            {type: "lock-state", state: "locked"},
            {type: "lock-state", state: "unknown"},
            {type: "source-removed"},
            {type: "destroy"}
        ];
        events.forEach(event => {
            let state = capture("private-source", {allowLive: true});
            state = Preview.reduceCapture(state, captureEvent(state, "capture-ready"));
            state = Preview.reduceCapture(state, {type: "popup-visible", visible: true});
            verify(state.live);
            state = Preview.reduceCapture(state, event.type === "source-removed" || event.type === "destroy"
                ? captureEvent(state, event.type, event) : event);
            verify(state.tornDown, JSON.stringify(event));
            verify(state.terminal, JSON.stringify(event));
            verify(!state.captureRequested, JSON.stringify(event));
            verify(!state.live, JSON.stringify(event));
            verify(!state.sourceAttached, JSON.stringify(event));
            verify(!state.popupVisible, JSON.stringify(event));
        });
        const unlocked = Preview.reduceCapture(capture("safe"), {type: "lock-state", state: "unlocked"});
        verify(!unlocked.tornDown);
        verify(unlocked.captureRequested);
    }
}
