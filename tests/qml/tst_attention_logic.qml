import QtQuick
import QtTest
import "../../core/AttentionLogic.js" as Attention

TestCase {
    name: "AttentionLogic"

    function app(id, notificationIds, extra) {
        return Object.assign({
            id: id,
            notificationIds: notificationIds || [id],
            pwaIds: [],
            browserIds: [],
            focused: false,
            launchPending: false,
            openedAtMs: 0,
            windows: []
        }, extra || {});
    }

    function row(id, timestampMs, extra) {
        return Object.assign({
            id: id,
            timestampMs: timestampMs,
            appId: "",
            pwaId: "",
            browserId: ""
        }, extra || {});
    }

    function policy(extra) {
        return Object.assign({
            enabled: true,
            soundEnabled: true,
            soundName: "bell",
            dnd: false
        }, extra || {});
    }

    function test_nativeUrgencyEligibility() {
        const apps = [app("app.alpha", [], {
                openedAtMs: 1000,
                windows: [
                    {
                        id: "window.alpha",
                        focused: false,
                        openedAtMs: 1000
                    }
                ]
            })];

        compare(Attention.nativeUrgency(apps, "window.alpha", 4001), {
            appId: "app.alpha",
            windowId: "window.alpha"
        });
        compare(Attention.nativeUrgency(apps, "window.alpha", 4000), null);

        apps[0].windows[0].focused = true;
        compare(Attention.nativeUrgency(apps, "window.alpha", 9000), null);
        apps[0].windows[0].focused = false;
        apps[0].focused = true;
        compare(Attention.nativeUrgency(apps, "window.alpha", 9000), null);
        apps[0].focused = false;
        apps[0].launchPending = true;
        compare(Attention.nativeUrgency(apps, "window.alpha", 9000), null);
    }

    function test_nativeUrgencyRejectsMalformedStaleAndAmbiguousIds() {
        const apps = [app("app.alpha", [], {
                windows: [
                    {
                        id: "window.alpha",
                        focused: false,
                        openedAtMs: 10
                    }
                ]
            })];
        compare(Attention.nativeUrgency(apps, "window.closed", 5000), null);
        compare(Attention.nativeUrgency(apps, "window.alpha", 5), null);
        compare(Attention.nativeUrgency(apps, "", 5000), null);
        compare(Attention.nativeUrgency([
            {
                id: "app.bad",
                windows: [
                    {
                        id: "window.alpha"
                    }
                ]
            }
        ], "window.alpha", 5000), null);
        apps.push(app("app.other", [], {
            windows: [
                {
                    id: "window.alpha",
                    focused: false,
                    openedAtMs: 10
                }
            ]
        }));
        compare(Attention.nativeUrgency(apps, "window.alpha", 5000), null);
    }

    function test_metadataContractsRejectContentFields() {
        const nativeApp = app("app.alpha", [], {
            windows: [
                {
                    id: "window.alpha",
                    focused: false,
                    openedAtMs: 1
                }
            ],
            title: "content"
        });
        compare(Attention.nativeUrgency([nativeApp], "window.alpha", 5000), null);

        const notificationApp = app("app.alpha");
        notificationApp.body = "content";
        compare(Attention.notificationTargets([notificationApp], row("notification.a", 1, {
            appId: "app.alpha"
        })), []);

        delete nativeApp.title;
        nativeApp.windows[0].title = "content";
        compare(Attention.nativeUrgency([nativeApp], "window.alpha", 5000), null);
    }

    function test_exactAttributionPrioritizesPwaThenUsesBrowserFallback() {
        const apps = [app("pwa.chat", [], {
                pwaIds: ["origin.chat"]
            }), app("browser", [], {
                browserIds: ["org.browser"]
            })];
        compare(Attention.notificationTargets(apps, row("notification.1", 7000, {
            pwaId: "origin.chat",
            browserId: "org.browser"
        })), ["pwa.chat"]);
        compare(Attention.notificationTargets(apps, row("notification.2", 7001, {
            pwaId: "origin.unknown",
            browserId: "org.browser"
        })), ["browser"]);
        compare(Attention.notificationTargets(apps, row("notification.3", 7002, {
            appId: "pwa.chat",
            browserId: "org.browser"
        })), ["pwa.chat"]);
        compare(Attention.notificationTargets(apps, row("notification.4", 7003, {
            appId: "PWA.CHAT"
        })), []);
    }

    function test_strongAmbiguityStopsWeakerIdentityFallback() {
        const apps = [app("pwa.one", [], {pwaIds:["origin.shared"]}),
            app("pwa.two", [], {pwaIds:["origin.shared"]}),
            app("browser", [], {browserIds:["org.browser"]})];
        compare(Attention.notificationTargets(apps, row("notification.ambiguous", 1, {
            pwaId: "origin.shared", browserId: "org.browser"
        })), []);
    }

    function test_collectionAndRetainedStateBoundsFailClosed() {
        const tooManyApps = [];
        for (let i = 0; i < 257; ++i) tooManyApps.push(app("app." + i));
        compare(Attention.notificationTargets(tooManyApps, row("notification", 1, {appId:"app.0"})), []);
        compare(Attention.nativeUrgency(tooManyApps, "window", 5000), null);

        const tooManyRows = [];
        for (let i = 0; i < 1025; ++i) tooManyRows.push(row("notification." + i, i, {appId:"app.alpha"}));
        let state = Attention.beginGeneration(Attention.newState(), "generation.a", []);
        const overflow = Attention.processNotifications(state, "generation.a", tooManyRows,
            [app("app.alpha")], policy(), 10000);
        verify(overflow.overflow);
        compare(overflow.matches, []);
        compare(Object.keys(overflow.state.seen).length, 0);
        compare(overflow.soundName, "");

        state = Attention.beginGeneration(state, "generation.b", tooManyRows);
        verify(state.overflow);
        compare(Object.keys(state.seen).length, 0);

        let nativeState = Attention.newState();
        for (let i = 0; i < 513; ++i)
            nativeState = Attention.recordNative(nativeState, {appId:"app.alpha", windowId:"window." + i});
        verify(nativeState.overflow);
        verify(Object.keys(nativeState.attention["app.alpha"].windows).length <= 512);
    }

    function test_attributionDoesNotDuplicateOrGuessAmbiguousIds() {
        const apps = [app("pwa.chat", ["pwa.chat"], {
                pwaIds: ["origin.chat"]
            }), app("pwa.chat", ["pwa.chat"], {
                pwaIds: ["origin.chat"]
            }), app("browser.one", [], {
                browserIds: ["org.browser"]
            }), app("browser.two", [], {
                browserIds: ["org.browser"]
            })];
        compare(Attention.notificationTargets(apps, row("notification.1", 1, {
            pwaId: "origin.chat"
        })), []);
        compare(Attention.notificationTargets(apps, row("notification.2", 2, {
            browserId: "org.browser"
        })), []);
        compare(Attention.notificationTargets([apps[0]], row("notification.3", 3, {
            appId: "pwa.chat",
            pwaId: "origin.chat"
        })), ["pwa.chat"]);
    }

    function test_generationBaselineAndIdDedupeIgnoreTimestamps() {
        const apps = [app("app.alpha")];
        let state = Attention.beginGeneration(Attention.newState(), "generation.a", [row("notification.old", 1000, {
                appId: "app.alpha"
            })]);
        let result = Attention.processNotifications(state, "generation.a", [row("notification.old", 1000, {
                appId: "app.alpha"
            }), row("notification.a", 2000, {
                appId: "app.alpha"
            }), row("notification.b", 2000, {
                appId: "app.alpha"
            })], apps, policy(), 10000);
        compare(result.matches, [
            {
                notificationId: "notification.a",
                appId: "app.alpha"
            },
            {
                notificationId: "notification.b",
                appId: "app.alpha"
            }
        ]);
        compare(result.soundName, "bell");

        state = result.state;
        result = Attention.processNotifications(state, "generation.a", [row("notification.a", 9000, {
                appId: "app.alpha"
            }), row("notification.b", 9001, {
                appId: "app.alpha"
            })], apps, policy(), 11000);
        compare(result.matches, []);
        compare(result.soundName, "");
    }

    function test_reconnectBaselinesReplayAndRejectsStaleGeneration() {
        const apps = [app("app.alpha")];
        let state = Attention.beginGeneration(Attention.newState(), "generation.a", []);
        let result = Attention.processNotifications(state, "generation.a", [row("notification.a", 1000, {
                appId: "app.alpha"
            })], apps, policy(), 10000);
        state = Attention.beginGeneration(result.state, "generation.b", [row("notification.a", 1000, {
                appId: "app.alpha"
            }), row("notification.replay", 2000, {
                appId: "app.alpha"
            })]);
        result = Attention.processNotifications(state, "generation.b", [row("notification.a", 1000, {
                appId: "app.alpha"
            }), row("notification.replay", 2000, {
                appId: "app.alpha"
            })], apps, policy(), 12000);
        compare(result.matches, []);

        result = Attention.processNotifications(result.state, "generation.a", [row("notification.stale", 3000, {
                appId: "app.alpha"
            })], apps, policy(), 12000);
        compare(result.matches, []);
        result = Attention.processNotifications(result.state, "generation.b", [row("notification.new", 2000, {
                appId: "app.alpha"
            })], apps, policy(), 12000);
        compare(result.matches, [
            {
                notificationId: "notification.new",
                appId: "app.alpha"
            }
        ]);
    }

    function test_malformedAndContentBearingSnapshotsFailClosed() {
        const apps = [app("app.alpha")];
        let state = Attention.beginGeneration(Attention.newState(), "generation.a", []);
        const unchanged = Attention.beginGeneration(state, " bad ", []);
        compare(unchanged.generation, "generation.a");
        const result = Attention.processNotifications(state, "generation.a", [null, row("", 1, {
                appId: "app.alpha"
            }), row("notification.bad-time", -1, {
                appId: "app.alpha"
            }), Object.assign(row("notification.private", 2, {
                appId: "app.alpha"
            }), {
                body: "private"
            }), Object.assign(row("notification.private2", 3, {
                appId: "app.alpha"
            }), {
                title: "private"
            }), row("notification.unknown", 4, {
                appId: "app.unknown"
            })], apps, policy(), 10000);
        compare(result.matches, []);
        verify(JSON.stringify(result).indexOf("private") === -1);
    }

    function test_notificationEligibilitySuppressesForegroundNewAndPendingApps() {
        const apps = [app("app.focused", [], {
                focused: true
            }), app("app.new", [], {
                openedAtMs: 8000
            }), app("app.pending", [], {
                launchPending: true
            }), app("app.eligible")];
        let state = Attention.beginGeneration(Attention.newState(), "generation.a", []);
        const result = Attention.processNotifications(state, "generation.a", [row("notification.focused", 1, {
                appId: "app.focused"
            }), row("notification.new", 2, {
                appId: "app.new"
            }), row("notification.pending", 3, {
                appId: "app.pending"
            }), row("notification.eligible", 4, {
                appId: "app.eligible"
            })], apps, policy(), 10000);
        compare(result.matches, [
            {
                notificationId: "notification.eligible",
                appId: "app.eligible"
            }
        ]);
    }

    function test_focusAndCloseCleanExactAttentionOnly() {
        const apps = [app("app.alpha"), app("app.alphabet")];
        let state = Attention.newState();
        state = Attention.recordNative(state, {
            appId: "app.alpha",
            windowId: "window.alpha"
        });
        state = Attention.recordNative(state, {
            appId: "app.alpha",
            windowId: "window.beta"
        });
        state = Attention.recordNative(state, {
            appId: "app.alphabet",
            windowId: "window.other"
        });
        verify(Attention.hintVisible(state, "app.alpha", true, apps));
        state = Attention.closeWindow(state, "window.alpha");
        verify(Attention.hintVisible(state, "app.alpha", true, apps));
        state = Attention.closeWindow(state, "window.beta");
        verify(!Attention.hintVisible(state, "app.alpha", true, apps));
        verify(Attention.hintVisible(state, "app.alphabet", true, apps));
        state = Attention.clearFocused(state, "app.alphabet");
        verify(!Attention.hintVisible(state, "app.alphabet", true, apps));

        state = Attention.recordNative(state, {
            appId: "app.alpha",
            windowId: "window.alpha"
        });
        state = Attention.closeApp(state, "app.alpha");
        verify(!Attention.hintVisible(state, "app.alpha", true, apps));
    }

    function test_hintVisibilityObeysPreferenceAndLiveFocus() {
        let state = Attention.recordNative(Attention.newState(), {
            appId: "app.alpha",
            windowId: "window.alpha"
        });
        const apps = [app("app.alpha")];
        verify(Attention.hintVisible(state, "app.alpha", true, apps));
        verify(!Attention.hintVisible(state, "app.alpha", false, apps));
        apps[0].focused = true;
        verify(!Attention.hintVisible(state, "app.alpha", true, apps));
        verify(!Attention.hintVisible(state, "app.unknown", true, apps));
    }

    function test_soundRequiresEnabledNamedNonDndEligibleMatch() {
        const match = [
            {
                notificationId: "notification.a",
                appId: "app.alpha"
            }
        ];
        compare(Attention.soundDecision({
            enabled: true,
            soundName: "bell"
        }, false, match), "bell");
        compare(Attention.soundDecision({
            enabled: false,
            soundName: "bell"
        }, false, match), "");
        compare(Attention.soundDecision({
            enabled: true,
            soundName: "none"
        }, false, match), "");
        compare(Attention.soundDecision({
            enabled: true,
            soundName: "bell"
        }, true, match), "");
        compare(Attention.soundDecision({
            enabled: true,
            soundName: "bell"
        }, false, []), "");
        compare(Attention.soundDecision({
            enabled: true,
            soundName: " bell "
        }, false, match), "");
        compare(Attention.soundDecision({
            enabled: true,
            soundName: "bell"
        }, "off", match), "");
    }

    function test_disabledNotificationAttentionDoesNotMutateOrSound() {
        const apps = [app("app.alpha")];
        const state = Attention.beginGeneration(Attention.newState(), "generation.a", []);
        const result = Attention.processNotifications(state, "generation.a", [row("notification.a", 1, {
                appId: "app.alpha"
            })], apps, policy({
            enabled: false
        }), 10000);
        compare(result.matches, []);
        compare(result.soundName, "");
        verify(!Attention.hintVisible(result.state, "app.alpha", true, apps));
    }
}
